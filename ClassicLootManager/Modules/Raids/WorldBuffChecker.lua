local _, CLM = ...

-- Spell catalog and schema evidence: docs/world-buff-checker-references.md.
local BUFFS = {
    {key = "dragonslayer", name = "Rallying Cry of the Dragonslayer", ids = {22888, 355363}, slot = 4},
    {key = "zandalar", name = "Spirit of Zandalar", ids = {24425, 355365}, slot = 6},
    {key = "songflower", name = "Songflower Serenade", ids = {15366}, slot = 7},
    {key = "fengus", name = "Fengus' Ferocity", ids = {22817}, slot = 1},
    {key = "moldar", name = "Mol'dar's Moxie", ids = {22818}, slot = 2},
    {key = "slipkik", name = "Slip'kik's Savvy", ids = {22820}, slot = 3},
    {key = "dmf", name = "Darkmoon Faire", ids = {23768, 23769, 23767, 23766, 23738, 23737, 23735, 23736}, slot = 8},
    {key = "warchief", name = "Warchief's Blessing", ids = {16609, 355366}, slot = 5},
}
local BY_SPELL, DMF = {}, {}
for _, buff in ipairs(BUFFS) do
    buff.minimumSeconds = (buff.key == "songflower" or buff.key == "warchief") and 3000 or 6600
    for _, id in ipairs(buff.ids) do
        BY_SPELL[id] = buff.key
        if buff.key == "dmf" then DMF[id] = true end
    end
end

local Checker = {}
local BOON = 349981
-- Safety bound, not a claimed Blizzard limit. Hitting it leaves absence UNKNOWN.
local MAX_AURAS = 255

local function number(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end

-- Keep the longest concrete observation, while retaining uncertainty in alternatives.
local function mergeObservation(current, candidate)
    if not candidate then return current end
    local best = current or candidate
    if number(candidate.remaining) and (not number(best.remaining) or candidate.remaining > best.remaining) then
        best = candidate
    end
    return {
        remaining = best.remaining, spellId = best.spellId,
        unknownDuration = (current and current.unknownDuration) or candidate.unknownDuration
            or not number(candidate.remaining),
    }
end

local function durationStatus(active, stored, minimum)
    local best
    for _, observation in pairs({active = active, stored = stored}) do
        if number(observation.remaining) and (not best or observation.remaining > best) then
            best = observation.remaining
        end
    end
    if best and best >= minimum then return "SUFFICIENT", best end
    if not active and not stored then return "NOT_OBSERVED", nil end
    if (active and active.unknownDuration) or (stored and stored.unknownDuration) then return "UNKNOWN", best end
    return "TOO_SHORT", best
end

local function call(api, method, ...)
    if type(api[method]) ~= "function" then return nil end
    local ok, first, second = pcall(api[method], ...)
    if ok then return first, second end
end

local function yes(value)
    return value == true or value == 1
end

local function defaultAPI()
    return {
        IsInRaid = IsInRaid, IsInGroup = IsInGroup,
        IsHardcore = CLM.IsHardcore, GetBuildInfo = GetBuildInfo, GetTime = GetTime,
        UnitExists = UnitExists, UnitGUID = UnitGUID, UnitName = UnitFullName,
        UnitIsVisible = UnitIsVisible, UnitIsConnected = UnitIsConnected,
        GetAuraDataByIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex,
    }
end

local function observe(api, unit, guid, now, schema)
    local sample = {active = {}, stored = {}, zero = {}, boons = {}, complete = false}
    sample.visible = yes(call(api, "UnitIsVisible", unit))
    sample.connected = yes(call(api, "UnitIsConnected", unit))
    local valid = true
    if type(api.GetAuraDataByIndex) == "function" then
        for index = 1, MAX_AURAS do
            local ok, aura = pcall(api.GetAuraDataByIndex, unit, index, "HELPFUL")
            if not ok then break end
            if aura == nil then sample.complete = valid; break end
            if type(aura) ~= "table" or not number(aura.spellId) or aura.spellId < 1 then
                valid = false
            else
                local key = BY_SPELL[aura.spellId]
                if key then
                    local remaining
                    if number(aura.expirationTime) and aura.expirationTime > 0 and number(now) then
                        remaining = math.max(0, aura.expirationTime - now)
                    end
                    sample.active[key] = mergeObservation(sample.active[key], {spellId = aura.spellId, remaining = remaining})
                elseif aura.spellId == BOON then
                    sample.boons[#sample.boons + 1] = aura
                end
            end
        end
    end
    -- Unit tokens may be reassigned during a scan. Do not attribute another GUID's auras.
    if call(api, "UnitGUID", unit) ~= guid then
        return {active = {}, stored = {}, zero = {}, boons = {}, complete = false}
    end
    sample.visible = sample.visible and yes(call(api, "UnitIsVisible", unit))
    sample.connected = sample.connected and yes(call(api, "UnitIsConnected", unit))
    sample.complete = sample.complete and sample.visible and sample.connected
    for _, buff in ipairs(BUFFS) do
        local allZero = #sample.boons > 0
        for _, aura in ipairs(sample.boons) do
            local value = type(aura.points) == "table" and aura.points[buff.slot] or nil
            if not schema or not number(value) then
                allZero = false
            elseif value > 0 then
                allZero = false
                local id = buff.key == "dmf" and aura.points[9] or nil
                if buff.key ~= "dmf" or DMF[id] then
                    sample.stored[buff.key] = mergeObservation(sample.stored[buff.key], {remaining = value, spellId = id})
                end
            end
        end
        sample.zero[buff.key] = allZero
    end
    return sample
end

local function evaluate(player, profile)
    player.buffs = {}
    player.counts = {active = 0, stored = 0, missing = 0, unknown = 0}
    player.durationWarnings, player.optionalDurationWarnings = 0, 0
    player.violations = {}
    for _, buff in ipairs(BUFFS) do
        local active, stored, absent
        for _, sample in ipairs(player.samples) do
            active = mergeObservation(active, sample.active[buff.key])
            stored = mergeObservation(stored, sample.stored[buff.key])
            -- End-of-enumeration and visibility alone do not prove buff absence.
            -- Require this buff's explicit zero in a schema-validated observed boon,
            -- as well as a stable, connected, visible and uninterrupted scan.
            if sample.complete and sample.zero[buff.key] then absent = true end
        end
        local evidence = active and "ACTIVE" or stored and "STORED" or absent and "MISSING" or "UNKNOWN"
        local required = buff.key ~= "warchief" and (buff.key ~= "dmf" or profile == "with_dmf")
        local result = {
            status = required and evidence or "NOT_REQUIRED", evidence = evidence,
            activeRemaining = active and active.remaining, activeSpellId = active and active.spellId,
            storedRemaining = stored and stored.remaining, storedSpellId = stored and stored.spellId,
        }
        result.durationStatus, result.bestRemaining = durationStatus(active, stored, buff.minimumSeconds)
        result.minimumSeconds = buff.minimumSeconds
        if result.durationStatus == "TOO_SHORT" then
            if required then player.durationWarnings = player.durationWarnings + 1
            else player.optionalDurationWarnings = player.optionalDurationWarnings + 1 end
        end
        if required and (evidence == "MISSING" or result.durationStatus == "TOO_SHORT") then
            player.violations[#player.violations + 1] = {
                buffKey = buff.key, name = buff.name,
                kind = evidence == "MISSING" and "MISSING" or "TOO_SHORT",
                minimumSeconds = buff.minimumSeconds, remaining = result.bestRemaining,
            }
        end
        player.buffs[buff.key] = result
        if required then
            local countKey = string.lower(evidence)
            player.counts[countKey] = player.counts[countKey] + 1
        end
    end
    local counts = player.counts
    player.status = counts.missing > 0 and "MISSING" or counts.unknown > 0 and "UNKNOWN"
        or counts.stored > 0 and "READY_STORED" or "READY_ACTIVE"
    player.penaltyEligible = #player.violations > 0
    player.samples = nil
end

function Checker:Initialize()
    -- Read-only, on-demand service. No events, timers, database or comms registration.
end

function Checker:GetBuffs()
    return BUFFS
end

function Checker:Scan(profile, api)
    api = api or defaultAPI()
    assert(profile == "with_dmf" or profile == "without_dmf", "Unknown world buff profile")
    local version, build = call(api, "GetBuildInfo")
    local result = {
        profile = profile, players = {}, skippedUnits = 0, scannedAt = call(api, "GetTime"),
        schemaConfirmed = version == "1.15.9" and tonumber(build) == 70003,
    }
    if not yes(call(api, "IsHardcore")) then result.error = "unsupported_client"; return result end
    local units = {"player"}
    if yes(call(api, "IsInRaid")) then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    elseif yes(call(api, "IsInGroup")) then
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end
    local byGUID = {}
    for _, unit in ipairs(units) do
        if yes(call(api, "UnitExists", unit)) then
            local guid = call(api, "UnitGUID", unit)
            if type(guid) == "string" and guid ~= "" then
                local player = byGUID[guid]
                if not player then
                    local name, realm = call(api, "UnitName", unit)
                    player = {guid = guid, name = name or unit, samples = {}, visible = false, connected = false}
                    if type(realm) == "string" and realm ~= "" then player.name = player.name .. "-" .. realm end
                    byGUID[guid] = player
                    result.players[#result.players + 1] = player
                end
                local sample = observe(api, unit, guid, result.scannedAt, result.schemaConfirmed)
                player.samples[#player.samples + 1] = sample
                player.visible = player.visible or sample.visible or false
                player.connected = player.connected or sample.connected or false
            else
                result.skippedUnits = result.skippedUnits + 1
            end
        end
    end
    for _, player in ipairs(result.players) do evaluate(player, profile) end
    table.sort(result.players, function(a, b)
        if a.name == b.name then return a.guid < b.guid end
        return a.name < b.name
    end)
    return result
end

CLM.RegisterModule("WorldBuffChecker", Checker)
