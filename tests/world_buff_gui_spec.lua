-- AceGUI and Blizzard are the external boundaries; the real scanner and GUI are loaded.
local widgets, calls = {}, 0
local function widget(kind)
    local w = {kind = kind, callbacks = {}, children = {}}
    for _, method in ipairs({"SetTitle","SetLayout","SetWidth","SetHeight","SetFullWidth","SetText","SetLabel",
        "SetValue","SetList","SetDisabled","SetDisplayCols","SetDisplayRows","EnableResize","EnableSelection"}) do
        w[method] = function(self, value) self[method .. "Value"] = value end
    end
    w.SetCallback = function(self, event, callback) self.callbacks[event] = callback end
    w.AddChild = function(self, child) self.children[#self.children+1] = child end
    w.ReleaseChildren = function(self) self.children = {} end
    w.SetData = function(self, data) self.data = data end
    w.RegisterEvents = function(self, events) self.events = events end
    w.ClearSelection = function() end
    w.Show = function(self) self.visible = true end
    w.Hide = function(self) self.visible = false end
    w.GetRow = function(self, index) return self.data[index] end
    widgets[#widgets+1] = w
    return w
end
local AceGUI = {Create = function(_, kind) return widget(kind) end}
LibStub = function(name)
    if name == "AceGUI-3.0" then return AceGUI end
    return {SORT_ASC = 1}
end
IsInRaid = function() return true end
IsInGroup = function() return true end
GetBuildInfo = function() return "1.15.9", "70003" end
GetTime = function() return 1000 end
UnitExists = function(unit) return unit == "player" or unit == "raid1" end
UnitGUID = function() return "synthetic-guid" end
UnitFullName = function() return "Synthetic", "TestRealm" end
UnitIsVisible = function() return true end
UnitIsConnected = function() return true end
date = os.date
C_UnitAuras = {GetAuraDataByIndex = function(_, index)
    calls = calls+1
    if index == 1 then return {spellId = 22817, expirationTime = 1060} end
    if index == 2 then return {spellId = 349981, points = {120,130,140,150,3538,170,180,190,23768}} end
end}
local CLM = {
    MODULES = {}, GUI = {}, CONSTANTS = {},
    IsHardcore = function() return true end,
    L = setmetatable({}, {__index = function(_, key) return key end}),
}
CLM.RegisterModule = function(name, module) CLM.MODULES[name] = module end
assert(loadfile("ClassicLootManager/Modules/Raids/WorldBuffChecker.lua"))("CLM", CLM)
assert(loadfile("ClassicLootManager/Modules/GUI/WorldBuffCheckerGUI.lua"))("CLM", CLM)
local gui = CLM.GUI.WorldBuffChecker
gui:Initialize()
gui:Show()
assert(calls == 0, "Opening the window must not scan")
local button, dropdown, rows, details
for _, w in ipairs(widgets) do
    if w.kind == "Button" and w.SetTextValue == "Scan raid" then button = w end
    if w.kind == "Dropdown" then dropdown = w end
    if w.kind == "CLMLibScrollingTable" then rows = w end
    if w.kind == "ScrollFrame" then details = w end
end
assert(button and dropdown and rows and details, "Required controls exist")
dropdown.callbacks.OnValueChanged(dropdown, "OnValueChanged", "without_dmf")
assert(calls == 0, "Changing profiles must not scan")
button.callbacks.OnClick(button)
assert(calls > 0 and #rows.data == 1, "Manual scan renders one row per GUID")
assert(rows.data[1].cols[2].value == 1, "Active requirement count")
assert(rows.data[1].cols[3].value == 5, "Stored requirement count without DMF")
rows.events.OnClick(nil,nil,nil,nil,nil,1,nil,rows)
local texts = {}
for _, child in ipairs(details.children) do texts[#texts+1] = child.SetTextValue or "" end
local detailText = table.concat(texts,"\n")
assert(detailText:find("ACTIVE",1,true) and detailText:find("STORED",1,true), "Distinct active/stored detail labels")
assert(detailText:find("Warchief",1,true) and detailText:find("NOT_REQUIRED",1,true), "Optional Warchief shown")
assert(detailText:find("58:58",1,true), "Validated stored Warchief duration shown")
local oldCalls = calls
dropdown.callbacks.OnValueChanged(dropdown, "OnValueChanged", "with_dmf")
assert(calls == oldCalls and #rows.data == 0, "Profile change clears stale results")
print("PASS manual GUI scan, profile change, GUID row and buff details")

-- Exercise the actual entry in the existing Raids UI, including a non-officer.
local optionsFeeder
CLM.LOG = {}
CLM.UTILS = {GreenYes = function() return "yes" end, RedNo = function() return "no" end}
CLM.CONSTANTS.ACL = {LEVEL = {ASSISTANT = 1}}
CLM.MODULES.ACL = {CheckLevel = function() return false end}
CLM.MODELS = {RosterConfiguration = {New = function() return {} end}}
CLM.GUI.Unified = {RegisterTab = function(_, _, _, _, _, _, verticalOptions) optionsFeeder = verticalOptions end}
CreateFrame = function() return {} end
assert(loadfile("ClassicLootManager/Modules/GUI/UnifiedGUI_Raids.lua"))("CLM", CLM)
local entry = optionsFeeder().args.world_buff_checker
assert(entry and not entry.hidden(), "Hardcore non-officer can open checker from Raids")
entry.func()
assert(calls == oldCalls, "Raids entry opens without scanning")
CLM.IsHardcore = function() return false end
assert(entry.hidden(), "Entry is hidden outside Hardcore")
print("PASS actual Raids UI entry and Hardcore gating")
