local _, CLM = ...
local Penalties, Session = {}, {}
Session.__index = Session

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function call(adapter, name, ...)
    if type(adapter[name]) ~= "function" then return nil end
    local ok, first, second = pcall(adapter[name], ...)
    if ok then return first, second end
end

local function contextError(context)
    if not context then return "CONTEXT_UNAVAILABLE" end
    if context.authorized ~= true then return "NOT_AUTHORIZED" end
    if type(context.raidUID) ~= "string" or context.raidUID == "" then return "NO_RAID" end
    if context.status ~= "CREATED" and context.status ~= "IN_PROGRESS" then return "RAID_CLOSED" end
    if type(context.rosterUID) ~= "number" or context.rosterUID <= 0 or context.rosterUID ~= context.rosterUID or context.rosterUID == math.huge or context.isDKP ~= true then return "NOT_DKP" end
    if context.ledgerReady ~= true then return "LEDGER_NOT_READY" end
end

local function amountValue(input, precision)
    if type(input) ~= "string" or not input:match("^%d+%.?%d*$") then return nil end
    if type(precision) ~= "number" or precision < 0 or precision > 10 or precision ~= math.floor(precision) then return nil end
    local fraction = input:match("%.(%d*)$") or ""
    if #fraction > precision then return nil end
    local value = tonumber(input)
    if not value or value ~= value or value <= 0 or value == math.huge then return nil end
    return value
end

local function signature(preview, context)
    local fields = {context.raidUID, tostring(context.rosterUID), context.status,
        tostring(context.ledgerHash), tostring(preview.amount), preview.profile}
    for _, target in ipairs(preview.targets) do fields[#fields + 1] = target.guid .. ":" .. target.priorPenalty end
    for _, entry in ipairs(preview.excluded) do fields[#fields + 1] = entry.guid .. ":" .. entry.reason end
    return table.concat(fields, "|")
end

local function build(self, input)
    local context = call(self.adapter, "ReadContext")
    local errorCode = contextError(context)
    if errorCode then return {error = errorCode, canBook = false} end
    if not self.scan then return {error = "NO_SCAN", canBook = false} end
    local amount = amountValue(input, context.precision)
    if not amount then return {error = "INVALID_AMOUNT", canBook = false} end
    local preview = {
        targets = {}, excluded = {}, count = 0, total = 0, amount = amount,
        raidUID = context.raidUID, rosterUID = context.rosterUID, raidName = context.raidName,
        profile = self.scan.profile, alreadyCount = 0, unverifiedCount = 0,
        -- No flag or adapter can enable unsafe regular DM entries.
        canBook = false, blockReason = "NO_ONCE_PROTOCOL",
    }
    local seen, accounts = {}, {}
    for _, player in ipairs(self.scan.players) do
        if not seen[player.guid] and #player.violations > 0 then
            seen[player.guid] = true
            local account, reason = call(self.adapter, "ResolveAccount", player.guid, context)
            if not account or type(account.guid) ~= "string" or account.guid == "" then
                preview.excluded[#preview.excluded + 1] = {guid = player.guid, name = player.name, reason = reason or "UNMAPPED"}
            else
                local target = accounts[account.guid]
                if not target then
                    target = {guid = account.guid, name = account.name, violations = {}, players = {}}
                    accounts[account.guid] = target
                end
                target.players[#target.players + 1] = player.name
                for _, violation in ipairs(player.violations) do
                    target.violations[#target.violations + 1] = copy(violation)
                end
            end
        end
    end
    for guid, target in pairs(accounts) do
        local state = call(self.adapter, "PenaltyState", context.raidUID, context.rosterUID, guid)
        if state == "PENALIZED" then
            preview.alreadyCount = preview.alreadyCount + 1
            preview.excluded[#preview.excluded + 1] = {guid = guid, name = target.name, reason = "ALREADY_PENALIZED"}
        else
            target.priorPenalty = state == "CLEAR" and "CLEAR" or "UNKNOWN"
            if target.priorPenalty == "UNKNOWN" then preview.unverifiedCount = preview.unverifiedCount + 1 end
            preview.targets[#preview.targets + 1] = target
        end
    end
    table.sort(preview.targets, function(a,b) return a.guid < b.guid end)
    table.sort(preview.excluded, function(a,b) return a.guid < b.guid end)
    preview.count = #preview.targets
    local factor = 10 ^ context.precision
    preview.total = math.floor(amount * preview.count * factor + 0.5) / factor
    if preview.total == math.huge then return {error = "INVALID_AMOUNT", canBook = false} end
    preview.signature = signature(preview, context)
    return preview
end

function Session:SetScan(scan)
    self.scan = scan and copy(scan) or nil
    self:InvalidatePreview()
end

function Session:InvalidatePreview()
    self.generation = self.generation + 1
    self.preview = nil
end

function Session:Preview(input)
    self:InvalidatePreview()
    local preview = build(self, input)
    if not preview.error then
        preview.token = self.generation
        self.preview = copy(preview)
        self.input = input
    end
    return preview
end

function Session:Confirm(token)
    local previous = self.preview
    self:InvalidatePreview()
    if not previous or token ~= previous.token then return false, "STALE_PREVIEW" end
    -- Repeat ACL, raid/roster, amount, account and prior-penalty checks.
    local current = build(self, self.input)
    if current.error then return false, current.error end
    if current.signature ~= previous.signature then return false, "STALE_PREVIEW" end
    -- Regular UpdatePoints/DM cannot enforce a synchronized raid/account key.
    -- User approval of a preview cannot override this backend prohibition.
    return false, "NO_ONCE_PROTOCOL"
end

local function defaultAdapter()
    return {
        ReadContext = function()
            local modules, constants = CLM.MODULES, CLM.CONSTANTS
            local authorized = modules.ACL and modules.ACL:CheckLevel(constants.ACL.LEVEL.ASSISTANT) or false
            if not authorized then return {authorized = false} end
            local raid = modules.RaidManager and modules.RaidManager:GetRaid()
            local roster = raid and raid:Roster()
            local uid = raid and raid:UID()
            if raid and modules.RaidManager:GetRaidByUid(uid) ~= raid then raid = nil end
            local rosterUID = roster and roster:UID()
            if roster and modules.RosterManager:GetRosterByUid(rosterUID) ~= roster then roster = nil end
            local lag, pending = modules.LedgerManager:Lag()
            local status = raid and raid:Status()
            return {
                authorized = authorized, raidUID = raid and uid, rosterUID = roster and rosterUID,
                raidName = raid and raid:Name(),
                status = status == constants.RAID_STATUS.CREATED and "CREATED"
                    or status == constants.RAID_STATUS.IN_PROGRESS and "IN_PROGRESS" or "CLOSED",
                isDKP = roster and roster:GetPointType() == constants.POINT_TYPE.DKP,
                precision = roster and roster:GetConfiguration("roundDecimals"),
                ledgerReady = lag == 0 and pending == 0 and not modules.LedgerManager:IsDisabled()
                    and not modules.LedgerManager:IsInIncoherentState()
                    and not modules.LedgerManager:IsTimeTraveling() and not modules.SandboxManager:IsSandbox(),
                ledgerHash = modules.LedgerManager:Hash(), roster = roster,
            }
        end,
        ResolveAccount = function(guid, context)
            local roster = context.roster
            local profiles = CLM.MODULES.ProfileManager
            local profile = profiles:GetProfileByGUID(guid)
            if not profile or profile:GUID() ~= guid then return nil, "UNMAPPED" end
            if profile:IsLocked() then return nil, "LOCKED" end
            if not roster:IsProfileInRoster(guid) then return nil, "WRONG_ROSTER" end
            local account = profile
            if profile:Main() ~= "" then
                account = profiles:GetProfileByGUID(profile:Main())
                if not account or account:GUID() ~= profile:Main() or account:Main() ~= "" then return nil, "UNRESOLVED_MAIN" end
            end
            if account:IsLocked() then return nil, "LOCKED" end
            if not roster:IsProfileInRoster(account:GUID()) then return nil, "WRONG_ROSTER" end
            return {guid = account:GUID(), name = account:Name()}
        end,
        PenaltyState = function()
            -- Legacy DM history is not an authoritative raid-once receipt.
            return "UNKNOWN"
        end,
    }
end

function Penalties:Initialize()
end

function Penalties:CanManage()
    local acl = CLM.MODULES.ACL
    return acl and acl:CheckLevel(CLM.CONSTANTS.ACL.LEVEL.ASSISTANT) or false
end

function Penalties:NewSession(adapter)
    return setmetatable({adapter = adapter or defaultAdapter(), generation = 0}, Session)
end

CLM.RegisterModule("WorldBuffPenalties", Penalties)
