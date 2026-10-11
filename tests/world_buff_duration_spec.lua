local CLM = {MODULES = {}}
CLM.RegisterModule = function(name, module) CLM.MODULES[name] = module end
assert(loadfile("ClassicLootManager/Modules/Raids/WorldBuffChecker.lua"))("CLM", CLM)
local checker = CLM.MODULES.WorldBuffChecker
local count = 0
local function eq(a,b) assert(a==b,"expected "..tostring(b)..", got "..tostring(a)) end
local function test(name, fn) fn(); count=count+1; print("PASS "..name) end
local function scan(auras, profile, now)
    local api = {
        IsInRaid=function() return false end, IsInGroup=function() return false end,
        IsHardcore=function() return true end, GetBuildInfo=function() return "1.15.9","70003" end,
        GetTime=function() return now or 1000 end, UnitExists=function() return true end,
        UnitGUID=function() return "synthetic" end, UnitName=function() return "Synthetic" end,
        UnitIsVisible=function() return true end, UnitIsConnected=function() return true end,
        GetAuraDataByIndex=function(_,i) return auras[i] end,
    }
    return checker:Scan(profile or "with_dmf",api).players[1]
end
local function active(id,seconds)
    return {spellId=id, expirationTime=seconds and (1000+seconds)}
end
local function stored(slot,seconds,dmf)
    local points = {}; points[slot]=seconds; points[9]=dmf or 23768
    return {spellId=349981,points=points,expirationTime=999999}
end
test("110 minutes is sufficient and 109:59 is too short",function()
    eq(scan({active(22888,6600)}).buffs.dragonslayer.durationStatus,"SUFFICIENT")
    eq(scan({active(22888,6599)}).buffs.dragonslayer.durationStatus,"TOO_SHORT")
end)

test("fixed thresholds apply to every active and stored buff",function()
    for _, b in ipairs({
        {22888,4,"dragonslayer",6600},{24425,6,"zandalar",6600},
        {22817,1,"fengus",6600},{22818,2,"moldar",6600},{22820,3,"slipkik",6600},
        {23768,8,"dmf",6600},{15366,7,"songflower",3000},{16609,5,"warchief",3000},
    }) do
        for _, delta in ipairs({0,-1}) do
            for _, aura in ipairs({active(b[1],b[4]+delta),stored(b[2],b[4]+delta)}) do
                local result=scan({aura}).buffs[b[3]]
                eq(result.durationStatus,delta==0 and "SUFFICIENT" or "TOO_SHORT")
                eq(result.minimumSeconds,b[4])
            end
        end
    end
end)
test("stored duration is frozen; active duration is calculated at scan",function()
    eq(scan({stored(4,6600)},nil,1010).buffs.dragonslayer.bestRemaining,6600)
    eq(scan({active(22888,6600)},nil,1010).buffs.dragonslayer.bestRemaining,6590)
end)
test("a sufficiently long active or stored alternative satisfies the buff",function()
    local p=scan({active(22888,6599),stored(4,6600)})
    eq(p.buffs.dragonslayer.status,"ACTIVE")
    eq(p.buffs.dragonslayer.durationStatus,"SUFFICIENT")
    eq(p.penaltyEligible,false)
    eq(scan({active(22888,6600),stored(4,6599)}).penaltyEligible,false)
end)
test("unknown alternate duration is not safely short",function()
    local p=scan({active(22888,nil),stored(4,6599)})
    eq(p.buffs.dragonslayer.durationStatus,"UNKNOWN")
    eq(p.penaltyEligible,false)
    eq(scan({active(22888,nil)}).penaltyEligible,false)
end)
test("duplicate active aliases retain a sufficient observation",function()
    for _, auras in ipairs({
        {active(22888,6600),active(355363,6599)},
        {active(355363,6599),active(22888,6600)},
    }) do
        local p=scan(auras)
        eq(p.buffs.dragonslayer.durationStatus,"SUFFICIENT")
        eq(p.penaltyEligible,false)
    end
end)
test("optional Warchief and optional DMF cannot cause penalties",function()
    local p=scan({active(16609,2999)})
    eq(p.optionalDurationWarnings,1)
    eq(p.durationWarnings,0)
    eq(p.penaltyEligible,false)
    p=scan({active(23768,6599)},"without_dmf")
    eq(p.penaltyEligible,false)
    eq(p.buffs.dmf.status,"NOT_REQUIRED")
    eq(scan({active(23768,6599)},"with_dmf").penaltyEligible,true)
end)
test("unknown evidence alone is never a penalty",function()
    local p=scan({})
    eq(p.counts.unknown,7)
    eq(p.penaltyEligible,false)
    eq(#p.violations,0)
end)
test("missing and short violations are independent of evidence class",function()
    local p=scan({stored(4,0)})
    eq(p.buffs.dragonslayer.status,"MISSING")
    eq(p.penaltyEligible,true)
    eq(p.violations[1].kind,"MISSING")
    p=scan({active(22888,6599),active(15366,2999)})
    eq(p.counts.active,2)
    eq(p.durationWarnings,2)
    eq(#p.violations,2)
    eq(p.violations[1].kind,"TOO_SHORT")
end)

print(count.." duration tests passed")
