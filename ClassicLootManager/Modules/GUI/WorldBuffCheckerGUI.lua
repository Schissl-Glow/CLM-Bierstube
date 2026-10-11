local _, CLM = ...
local AceGUI = LibStub("AceGUI-3.0")
local COLORS = {
    ACTIVE = "44dd66", STORED = "55aaff", MISSING = "ff6666",
    UNKNOWN = "ffcc55", NOT_REQUIRED = "aaaaaa",
    READY_ACTIVE = "44dd66", READY_STORED = "55aaff",
}
local STATUS_LABELS = {
    ACTIVE = CLM.L["ACTIVE"],
    STORED = CLM.L["STORED"],
    MISSING = CLM.L["MISSING"],
    UNKNOWN = CLM.L["UNKNOWN"],
    NOT_REQUIRED = CLM.L["NOT_REQUIRED"],
    READY_ACTIVE = CLM.L["READY_ACTIVE"],
    READY_STORED = CLM.L["READY_STORED"],
}
local GUI = {}

local function statusText(status)
    return "|cff" .. (COLORS[status] or "ffffff") .. (STATUS_LABELS[status] or status) .. "|r"
end

local function duration(seconds)
    if seconds == nil then return CLM.L["Duration unknown"] end
    seconds = math.floor(seconds)
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function label(parent, text)
    local control = AceGUI:Create("Label")
    control:SetFullWidth(true)
    control:SetText(text)
    parent:AddChild(control)
    return control
end

local PENALTY_MESSAGES = {
    NO_ONCE_PROTOCOL = CLM.L["Booking disabled: synchronized once-per-raid penalties are not available."],
    CONTEXT_UNAVAILABLE = CLM.L["Raid context is unavailable."],
    NOT_AUTHORIZED = CLM.L["Point permissions are required."],
    NO_RAID = CLM.L["No current CLM raid."],
    RAID_CLOSED = CLM.L["Only CREATED or IN_PROGRESS raids can be used."],
    NOT_DKP = CLM.L["A valid DKP roster is required."],
    LEDGER_NOT_READY = CLM.L["Ledger replay, sandbox or time travel prevents a reliable preview."],
    NO_SCAN = CLM.L["Scan the raid first."],
    INVALID_AMOUNT = CLM.L["Enter a finite positive DKP amount within roster precision."],
    UNMAPPED = CLM.L["Player cannot be mapped."],
    LOCKED = CLM.L["Profile or point account is locked."],
    WRONG_ROSTER = CLM.L["Player or point account is outside the roster."],
    UNRESOLVED_MAIN = CLM.L["Main/alt link cannot be resolved safely."],
    ALREADY_PENALIZED = CLM.L["Already penalized."],
    STALE_PREVIEW = CLM.L["Preview expired. Create a new preview."],
}

local function penaltyMessage(code)
    return PENALTY_MESSAGES[code] or CLM.L["Booking is blocked."]
end

function GUI:InvalidatePenaltyPreview(clearScan)
    if clearScan then self.penaltySession:SetScan(nil)
    else self.penaltySession:InvalidatePreview() end
    if self.penaltyWindow then self.penaltyWindow:Hide() end
end

function GUI:ShowPenaltyPreview()
    local preview = self.penaltySession:Preview(self.penaltyAmount)
    if self.penaltyWindow then AceGUI:Release(self.penaltyWindow) end
    local window = AceGUI:Create("Window")
    self.penaltyWindow = window
    window:SetTitle(CLM.L["DKP penalty preview"])
    window:SetWidth(760)
    window:SetHeight(620)
    window:EnableResize(false)
    window:SetLayout("Flow")
    window:SetCallback("OnClose", function()
        window:Hide()
        self.penaltySession:InvalidatePreview()
    end)
    if preview.error then
        label(window, penaltyMessage(preview.error))
        window:Show()
        return
    end
    label(window, string.format(CLM.L["CLM raid: %s | Roster: %s"],
        (preview.raidName or "") .. " [" .. preview.raidUID .. "]", tostring(preview.rosterUID)))
    label(window, string.format(CLM.L["Potential point accounts: %d | Total deduction: %s DKP"],
        preview.count, tostring(preview.total)))
    label(window, string.format(CLM.L["Confirmed prior penalties: %d | Unverified accounts: %d"],
        preview.alreadyCount, preview.unverifiedCount))
    label(window, CLM.L["This is a preview. No points have been booked."])
    local status = label(window, "|cffffff00" .. penaltyMessage(preview.blockReason) .. "|r")
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("Flow")
    scroll:SetFullWidth(true)
    scroll:SetHeight(330)
    window:AddChild(scroll)
    for _, target in ipairs(preview.targets) do
        label(scroll, (target.name or target.guid) .. ": -" .. tostring(preview.amount)
            .. " DKP (" .. table.concat(target.players, ", ") .. ")")
        for _, violation in ipairs(target.violations) do
            local text = violation.name .. ": " .. (violation.kind == "MISSING" and CLM.L["MISSING"] or CLM.L["Too short"])
            if violation.kind == "TOO_SHORT" then
                text = text .. " (" .. duration(violation.remaining) .. " < " .. duration(violation.minimumSeconds) .. ")"
            end
            label(scroll, text)
        end
        if target.priorPenalty == "UNKNOWN" then label(scroll, CLM.L["Prior penalty status cannot be verified."]) end
    end
    for _, entry in ipairs(preview.excluded) do
        label(scroll, entry.name .. ": " .. penaltyMessage(entry.reason))
    end
    local confirm = AceGUI:Create("Button")
    confirm:SetText(string.format(CLM.L["Confirm deduction: %s DKP"], tostring(preview.total)))
    confirm:SetFullWidth(true)
    confirm:SetDisabled(not preview.canBook)
    confirm:SetCallback("OnClick", function()
        local _, reason = self.penaltySession:Confirm(preview.token)
        status:SetText(penaltyMessage(reason))
        confirm:SetDisabled(true)
    end)
    window:AddChild(confirm)
    window:Show()
end

function GUI:Initialize()
    self.profile = "with_dmf"
    self.penaltyAmount = "10"
    self.penaltySession = CLM.MODULES.WorldBuffPenalties:NewSession()
end

function GUI:ShowDetails(player)
    self.details:ReleaseChildren()
    if not player then
        label(self.details, CLM.L["Select a player for buff details."])
        return
    end
    label(self.details, player.name)
    for _, buff in ipairs(CLM.MODULES.WorldBuffChecker:GetBuffs()) do
        local observation = player.buffs[buff.key]
        local text = buff.name .. ": " .. statusText(observation.status)
        if observation.status == "NOT_REQUIRED" then
            text = text .. " - " .. statusText(observation.evidence)
        end
        if observation.activeSpellId then
            text = text .. " | " .. CLM.L["Active remaining at scan"] .. ": " .. duration(observation.activeRemaining)
        end
        if observation.storedRemaining then
            text = text .. " | " .. CLM.L["Stored remaining (frozen)"] .. ": " .. duration(observation.storedRemaining)
            if observation.storedSpellId then text = text .. " (ID " .. observation.storedSpellId .. ")" end
        end
        if buff.key == "warchief" then text = text .. " | " .. CLM.L["Warchief is optional and excluded from required counts."] end
        if observation.durationStatus == "TOO_SHORT" then
            text = text .. " | |cffffff00" .. CLM.L["Too short"] .. ": "
                .. duration(observation.bestRemaining) .. " < " .. duration(observation.minimumSeconds) .. "|r"
        elseif observation.durationStatus == "UNKNOWN" then
            text = text .. " | " .. CLM.L["Duration unknown"]
        end
        label(self.details, text)
    end
    if not player.visible or not player.connected then
        label(self.details, CLM.L["Not visible or offline: only positive observations are retained."])
    end
end

function GUI:Scan()
    self:InvalidatePenaltyPreview(true)
    local result = CLM.MODULES.WorldBuffChecker:Scan(self.profile)
    self.result = result
    self.penaltySession:SetScan(result)
    local rows = {}
    for _, player in ipairs(result.players) do
        local counts = player.counts
        local overall = statusText(player.status)
        if player.durationWarnings > 0 and counts.missing == 0 and counts.unknown == 0 then
            overall = "|cffffff00" .. CLM.L["Duration warning"] .. "|r"
        end
        rows[#rows + 1] = {player = player, cols = {
            {value = player.name}, {value = counts.active, color = {r = 0.27, g = 0.87, b = 0.4}},
            {value = counts.stored, color = {r = 0.33, g = 0.67, b = 1}},
            {value = counts.missing}, {value = counts.unknown}, {value = overall},
            {value = tostring(player.durationWarnings) .. " (+" .. tostring(player.optionalDurationWarnings) .. ")",
                color = {r = 1, g = 0.85, b = 0.2}},
        }}
    end
    self.rows:ClearSelection()
    self.rows:SetData(rows)
    self:ShowDetails(nil)
    local text = string.format(CLM.L["Manual scan: %d players. Results remain unchanged until the next scan."], #rows)
    if result.error then text = CLM.L["World Buff Checker requires Classic Hardcore."] end
    if not result.schemaConfirmed then text = text .. " " .. CLM.L["Chronoboon schema is unverified for this client."] end
    if result.skippedUnits > 0 then
        text = text .. " " .. string.format(CLM.L["%d units could not be identified."], result.skippedUnits)
    end
    self.summary:SetText(text)
end

function GUI:CreateWindow()
    local window = AceGUI:Create("Window")
    window:SetTitle("World Buff Checker - v1.1 TEST")
    window:SetWidth(980)
    window:SetHeight(730)
    window:EnableResize(false)
    window:SetLayout("Flow")
    window:SetCallback("OnClose", function() window:Hide() end)
    self.window = window

    local profile = AceGUI:Create("Dropdown")
    profile:SetLabel(CLM.L["Check profile"])
    profile:SetWidth(230)
    profile:SetList({with_dmf = CLM.L["With DMF"], without_dmf = CLM.L["Without DMF"]}, {"with_dmf", "without_dmf"})
    profile:SetValue(self.profile)
    profile:SetCallback("OnValueChanged", function(_, _, value)
        self:InvalidatePenaltyPreview(true)
        self.profile = value
        self.result = nil
        self.rows:ClearSelection()
        self.rows:SetData({})
        self:ShowDetails(nil)
        self.summary:SetText(CLM.L["Profile changed. Scan the raid again."])
    end)
    window:AddChild(profile)
    local scan = AceGUI:Create("Button")
    scan:SetText(CLM.L["Scan raid"])
    scan:SetWidth(180)
    scan:SetDisabled(not CLM.IsHardcore())
    scan:SetCallback("OnClick", function() self:Scan() end)
    window:AddChild(scan)
    local amount = AceGUI:Create("EditBox")
    amount:SetLabel(CLM.L["DKP deduction per player"])
    amount:SetWidth(180)
    amount:SetText(self.penaltyAmount)
    amount:DisableButton(true)
    amount:SetDisabled(not CLM.MODULES.WorldBuffPenalties:CanManage())
    amount:SetCallback("OnTextChanged", function(_, _, value)
        self.penaltyAmount = value
        self:InvalidatePenaltyPreview(false)
    end)
    window:AddChild(amount)
    self.amountInput = amount
    local deduct = AceGUI:Create("Button")
    deduct:SetText(CLM.L["Deduct DKP"])
    deduct:SetWidth(180)
    deduct:SetDisabled(not CLM.MODULES.WorldBuffPenalties:CanManage())
    deduct:SetCallback("OnClick", function() self:ShowPenaltyPreview() end)
    window:AddChild(deduct)
    self.deductButton = deduct

    label(window, CLM.L["Six common buffs are required; DMF follows the profile. Warchief is optional."])
    self.summary = label(window, CLM.L["No scan yet. Only the current Blizzard group is checked."])
    local rows = AceGUI:Create("CLMLibScrollingTable")
    rows:SetDisplayCols({
        {name = CLM.L["Player"], width = 180, sort = LibStub("ScrollingTable").SORT_ASC},
        {name = CLM.L["ACTIVE"], width = 65}, {name = CLM.L["STORED"], width = 90},
        {name = CLM.L["MISSING"], width = 75}, {name = CLM.L["UNKNOWN"], width = 90},
        {name = CLM.L["Overall status"], width = 190},
        {name = CLM.L["Duration warnings (+optional)"], width = 100},
    })
    rows:SetDisplayRows(13, 18)
    rows:EnableSelection(true)
    rows:RegisterEvents({OnClick = function(_, _, _, _, _, realrow, _, scrollingTable)
        local row = scrollingTable:GetRow(realrow)
        if row then self:ShowDetails(row.player) end
        return true
    end})
    rows:SetData({})
    window:AddChild(rows)
    self.rows = rows
    local details = AceGUI:Create("ScrollFrame")
    details:SetLayout("Flow")
    details:SetFullWidth(true)
    details:SetHeight(250)
    window:AddChild(details)
    self.details = details
    self:ShowDetails(nil)
end

function GUI:Show()
    if not self.window then self:CreateWindow() end
    self.window:Show()
    self.rows:Show()
    local allowed = CLM.MODULES.WorldBuffPenalties:CanManage()
    self.amountInput:SetDisabled(not allowed)
    self.deductButton:SetDisabled(not allowed)
end

CLM.GUI.WorldBuffChecker = GUI
