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

function GUI:Initialize()
    self.profile = "with_dmf"
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
            text = text .. " â€” " .. statusText(observation.evidence)
        end
        if observation.activeSpellId then
            text = text .. " | " .. CLM.L["Active remaining at scan"] .. ": " .. duration(observation.activeRemaining)
        end
        if observation.storedRemaining then
            text = text .. " | " .. CLM.L["Stored remaining (frozen)"] .. ": " .. duration(observation.storedRemaining)
            if observation.storedSpellId then text = text .. " (ID " .. observation.storedSpellId .. ")" end
        end
        if buff.key == "warchief" then text = text .. " | " .. CLM.L["Warchief is optional and excluded from required counts."] end
        label(self.details, text)
    end
    if not player.visible or not player.connected then
        label(self.details, CLM.L["Not visible or offline: only positive observations are retained."])
    end
end

function GUI:Scan()
    local result = CLM.MODULES.WorldBuffChecker:Scan(self.profile)
    self.result = result
    local rows = {}
    for _, player in ipairs(result.players) do
        local counts = player.counts
        rows[#rows + 1] = {player = player, cols = {
            {value = player.name}, {value = counts.active, color = {r = 0.27, g = 0.87, b = 0.4}},
            {value = counts.stored, color = {r = 0.33, g = 0.67, b = 1}},
            {value = counts.missing}, {value = counts.unknown}, {value = statusText(player.status)},
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
    window:SetTitle("World Buff Checker â€” v1 TEST")
    window:SetWidth(900)
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

    label(window, CLM.L["Six common buffs are required; DMF follows the profile. Warchief is optional."])
    self.summary = label(window, CLM.L["No scan yet. Only the current Blizzard group is checked."])
    local rows = AceGUI:Create("CLMLibScrollingTable")
    rows:SetDisplayCols({
        {name = CLM.L["Player"], width = 180, sort = LibStub("ScrollingTable").SORT_ASC},
        {name = CLM.L["ACTIVE"], width = 65}, {name = CLM.L["STORED"], width = 90},
        {name = CLM.L["MISSING"], width = 75}, {name = CLM.L["UNKNOWN"], width = 90},
        {name = CLM.L["Overall status"], width = 230},
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
end

CLM.GUI.WorldBuffChecker = GUI
