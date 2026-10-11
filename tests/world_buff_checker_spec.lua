-- Run from the repository root with Lua 5.1. Identities and times are synthetic.
local CLM = { MODULES = {}, CONSTANTS = {}, IsHardcore = function() return true end }
CLM.RegisterModule = function(name, module) CLM.MODULES[name] = module end
assert(loadfile("ClassicLootManager/Modules/Raids/WorldBuffChecker.lua"))("ClassicLootManager", CLM)
local checker = CLM.MODULES.WorldBuffChecker
local tests = 0
local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, run)
    local ok, err = pcall(run)
    assert(ok, name .. ": " .. tostring(err))
    tests = tests + 1
    print("PASS " .. name)
end
local function apiFor(units, raid)
    return {
        IsInRaid = function() return raid or false end,
        IsInGroup = function() return units.party1 ~= nil end,
        IsHardcore = function() return true end,
        GetBuildInfo = function() return "1.15.9", "70003" end,
        GetTime = function() return 1000 end,
        UnitExists = function(unit) return units[unit] ~= nil end,
        UnitGUID = function(unit) return units[unit] and units[unit].guid end,
        UnitName = function(unit) return unit, "TestRealm" end,
        UnitIsVisible = function(unit) return units[unit].visible ~= false end,
        UnitIsConnected = function(unit) return units[unit].connected ~= false end,
        GetAuraDataByIndex = function(unit, index, filter)
            eq(filter, "HELPFUL")
            return (units[unit].auras or {})[index]
        end,
    }
end
local function boon(points)
    return { spellId = 349981, points = points, expirationTime = 999999 }
end

test("full Chronoboon for self and another raid member", function()
    local api = apiFor({
        player = { guid = "self", auras = {boon({120, 130, 140, 150, 160, 170, 180, 190, 23768})} },
        raid2 = { guid = "other", auras = {boon({120, 130, 140, 150, 160, 170, 180, 190, 23769})} },
    }, true)
    local result = checker:Scan("with_dmf", api)
    eq(#result.players, 2)
    for _, player in ipairs(result.players) do
        eq(player.counts.stored, 7)
        eq(player.counts.unknown, 0)
        eq(player.buffs.fengus.storedRemaining, 120)
        eq(player.buffs.dmf.storedRemaining, 190)
        eq(player.buffs.warchief.status, "NOT_REQUIRED")
        eq(player.buffs.warchief.evidence, "STORED")
    end
end)


test("remote player with only Dire Maul buffs stored", function()
    local result = checker:Scan("with_dmf", apiFor({
        raid1 = {guid = "three", auras = {boon({900, 800, 700, 0, 0, 0, 0, 0, 0})}},
    }, true))
    local player = result.players[1]
    eq(player.counts.stored, 3)
    eq(player.counts.missing, 4)
    eq(player.counts.unknown, 0)
end)

test("invisible raid member with two unrelated auras is UNKNOWN", function()
    local player = checker:Scan("with_dmf", apiFor({
        raid1 = {guid = "distant", visible = false, auras = {{spellId = 1}, {spellId = 2}}},
    }, true)).players[1]
    eq(player.counts.missing, 0)
    eq(player.counts.unknown, 7)
end)

test("zero is absence but an omitted points slot is UNKNOWN", function()
    local player = checker:Scan("with_dmf", apiFor({
        player = {guid = "sparse", auras = {boon({[1] = 0, [2] = 120})}},
    })).players[1]
    eq(player.buffs.fengus.status, "MISSING")
    eq(player.buffs.moldar.status, "STORED")
    eq(player.buffs.slipkik.status, "UNKNOWN")
end)

test("nil points and unknown schema do not claim stored absence", function()
    for _, points in ipairs({false, {}}) do
        local player = checker:Scan("with_dmf", apiFor({
            player = {guid = "no-points", auras = {boon(points or nil)}},
        })).players[1]
        eq(player.counts.unknown, 7)
        eq(player.counts.missing, 0)
    end
    local api = apiFor({player = {guid = "new-client", auras = {boon({1,2,3,4,5,6,7,8,23768})}}})
    api.GetBuildInfo = function() return "1.15.9", "70004" end
    local result = checker:Scan("with_dmf", api)
    eq(result.schemaConfirmed, false)
    eq(result.players[1].counts.unknown, 7)
end)

test("all eight Sayge variants qualify active and stored", function()
    for _, id in ipairs({23768,23769,23767,23766,23738,23737,23735,23736}) do
        local player = checker:Scan("with_dmf", apiFor({player = {
            guid = "sayge", auras = {{spellId = id}, boon({0,0,0,0,0,0,0,1800,id})},
        }})).players[1]
        eq(player.buffs.dmf.status, "ACTIVE")
        eq(player.buffs.dmf.storedRemaining, 1800)
        eq(player.buffs.dmf.storedSpellId, id)
    end
end)

test("unidentified DMF variant with a positive timer stays UNKNOWN", function()
    for _, id in ipairs({0, 12345, false}) do
        local player = checker:Scan("with_dmf", apiFor({player = {
            guid = "unknown-dmf", auras = {boon({0,0,0,0,0,0,0,100,id or nil})},
        }})).players[1]
        eq(player.buffs.dmf.status, "UNKNOWN")
    end
end)

test("active and stored observations coexist without double counting requirements", function()
    local api = apiFor({player = {guid = "mixed", auras = {
        {spellId = 22817, expirationTime = 1060}, boon({120,130,140,150,160,170,180,190,23768}),
    }}})
    local player = checker:Scan("with_dmf", api).players[1]
    eq(player.counts.active, 1)
    eq(player.counts.stored, 6)
    eq(player.buffs.fengus.activeRemaining, 60)
    eq(player.buffs.fengus.storedRemaining, 120)
    api.GetTime = function() return 1020 end
    player = checker:Scan("with_dmf", api).players[1]
    eq(player.buffs.fengus.activeRemaining, 40)
    eq(player.buffs.fengus.storedRemaining, 120)
end)

test("player and raid1 are one GUID with merged positive observations", function()
    local result = checker:Scan("without_dmf", apiFor({
        player = {guid = "same", auras = {{spellId = 22817}}},
        raid1 = {guid = "same", visible = false, auras = {{spellId = 24425}}},
    }, true))
    eq(#result.players, 1)
    eq(result.players[1].counts.active, 2)
end)

test("party and solo tokens work without a CLM raid or peer addon", function()
    local result = checker:Scan("without_dmf", apiFor({
        player = {guid = "self"}, party1 = {guid = "party"}, party4 = {guid = "last"},
    }))
    eq(#result.players, 3)
    eq(result.players[1].counts.missing, 6)
    eq(result.players[1].buffs.dmf.status, "NOT_REQUIRED")
end)

test("canonical and evidenced alias IDs are recognized", function()
    for _, entry in ipairs({
        {22888,"dragonslayer"},{355363,"dragonslayer"},{24425,"zandalar"},{355365,"zandalar"},
        {15366,"songflower"},{22817,"fengus"},{22818,"moldar"},{22820,"slipkik"},
        {16609,"warchief"},{355366,"warchief"},
    }) do
        local player = checker:Scan("with_dmf", apiFor({player = {
            guid = "active", auras = {{spellId = entry[1]}},
        }})).players[1]
        eq(player.buffs[entry[2]].evidence, "ACTIVE")
    end
end)

test("validated Warchief slot 5 is stored but still optional", function()
    local player = checker:Scan("without_dmf", apiFor({raid1 = {
        guid = "warchief", auras = {boon({0,0,0,0,3538,0,0,0,0})},
    }}, true)).players[1]
    eq(player.buffs.warchief.status, "NOT_REQUIRED")
    eq(player.buffs.warchief.evidence, "STORED")
    eq(player.buffs.warchief.storedRemaining, 3538)
    eq(player.counts.missing, 6)
    eq(player.counts.stored, 0)
end)

test("disconnected units retain positive evidence but no negative claims", function()
    local player = checker:Scan("with_dmf", apiFor({raid1 = {
        guid = "offline", connected = false, auras = {{spellId = 22817}},
    }}, true)).players[1]
    eq(player.counts.active, 1)
    eq(player.counts.unknown, 6)
    eq(player.counts.missing, 0)
end)

test("API failure and malformed aura preserve earlier positives", function()
    for _, broken in ipairs({"error", "malformed"}) do
        local api = apiFor({player = {guid = "partial"}})
        api.GetAuraDataByIndex = function(_, index)
            if index == 1 then return {spellId = 22817} end
            if index == 2 then
                if broken == "error" then error("not accessible") end
                return {}
            end
        end
        local player = checker:Scan("with_dmf", api).players[1]
        eq(player.counts.active, 1)
        eq(player.counts.unknown, 6)
    end
end)

test("safety bound and unavailable aura API cannot prove absence", function()
    local api = apiFor({player = {guid = "bound"}})
    api.GetAuraDataByIndex = function() return {spellId = 1} end
    eq(checker:Scan("with_dmf", api).players[1].counts.unknown, 7)
    api.GetAuraDataByIndex = nil
    eq(checker:Scan("with_dmf", api).players[1].counts.unknown, 7)
end)

test("unvalidated fields do not erase reliable stored positives", function()
    local player = checker:Scan("with_dmf", apiFor({player = {
        guid = "sparse", visible = false, auras = {boon({[1] = 120, [4] = 0})},
    }})).players[1]
    eq(player.buffs.fengus.status, "STORED")
    eq(player.buffs.dragonslayer.status, "UNKNOWN")
    eq(player.counts.missing, 0)
end)

test("invalid durations remain UNKNOWN", function()
    for _, value in ipairs({-1, "120", math.huge, 0/0}) do
        local player = checker:Scan("with_dmf", apiFor({player = {
            guid = "invalid-duration", auras = {boon({[1] = value})},
        }})).players[1]
        eq(player.buffs.fengus.status, "UNKNOWN")
    end
end)

test("changing GUID discards observations that cannot be attributed", function()
    local api = apiFor({player = {guid = "old", auras = {{spellId = 22817}}}})
    local calls = 0
    api.UnitGUID = function() calls = calls + 1; return calls == 1 and "old" or "new" end
    local player = checker:Scan("with_dmf", api).players[1]
    eq(player.counts.unknown, 7)
    eq(player.counts.active, 0)
end)

test("unsupported client does not scan auras", function()
    local api = apiFor({player = {guid = "retail"}})
    api.IsHardcore = function() return false end
    api.GetAuraDataByIndex = function() error("must not scan") end
    eq(checker:Scan("with_dmf", api).error, "unsupported_client")
end)


test("eight unique players, five boons including invisible P05, three unknown", function()
    local units = {}
    for i=1,8 do
        units["raid"..i] = {guid = "synthetic-"..i, visible = i < 5}
        if i<=5 then
            units["raid"..i].auras = {boon({120,130,140,150,3538,170,180,190,23769})}
        else
            units["raid"..i].auras = {{spellId = 1},{spellId = 2}}
        end
    end
    units.player = units.raid1
    local result = checker:Scan("with_dmf", apiFor(units, true))
    eq(#result.players,8)
    local stored, unknown = 0,0
    for _, player in ipairs(result.players) do
        if player.counts.stored == 7 then stored = stored+1
        elseif player.counts.unknown == 7 then unknown = unknown+1 end
        eq(player.counts.missing,0)
        if player.guid == "synthetic-5" then
            eq(player.visible,false)
            eq(player.buffs.warchief.evidence,"STORED")
            eq(player.buffs.warchief.storedRemaining,3538)
        end
    end
    eq(stored,5)
    eq(unknown,3)
end)

test("visibility lost during enumeration does not establish absence", function()
    local api = apiFor({player = {guid = "moving"}})
    local reads = 0
    api.UnitIsVisible = function() reads=reads+1; return reads==1 end
    eq(checker:Scan("with_dmf",api).players[1].counts.unknown,7)
end)

print(tostring(tests) .. " world buff tests passed")
