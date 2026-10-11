local CLM = {MODULES = {}}
CLM.RegisterModule = function(name,module) CLM.MODULES[name]=module end
assert(loadfile("ClassicLootManager/Modules/Raids/WorldBuffPenalties.lua"))("CLM",CLM)
local service=CLM.MODULES.WorldBuffPenalties
local function eq(a,b) assert(a==b,"expected "..tostring(b)..", got "..tostring(a)) end
local function fixture()
    local state={authorized=true,raidUID="raid-1",rosterUID=7,status="CREATED",isDKP=true,precision=2,ledgerReady=true,ledgerHash=1}
    local accounts={a={guid="main",name="Main"},b={guid="main",name="Main"},c={guid="other",name="Other"}}
    local charged={}
    local adapter={
        ReadContext=function() return state end,
        ResolveAccount=function(guid) return accounts[guid], "UNMAPPED" end,
        PenaltyState=function(_,_,guid) return charged[guid] or "UNKNOWN" end,
    }
    local snapshot={profile="with_dmf",players={
        {guid="a",name="Alt",violations={{buffKey="fengus",name="Fengus",kind="TOO_SHORT",remaining=6599,minimumSeconds=6600}}},
        {guid="b",name="Main",violations={{buffKey="dmf",name="DMF",kind="MISSING"}}},
        {guid="c",name="Other",violations={{buffKey="songflower",name="Songflower",kind="TOO_SHORT",remaining=2999,minimumSeconds=3000}}},
    }}
    return state,accounts,charged,adapter,snapshot
end
local state,accounts,charged,adapter,snapshot=fixture()
local session=service:NewSession(adapter)
session:SetScan(snapshot)
local preview=session:Preview("10.50")
eq(preview.count,2)
eq(preview.total,21)
eq(preview.unverifiedCount,2)
eq(preview.canBook,false)
eq(preview.blockReason,"NO_ONCE_PROTOCOL")
local ok,reason=session:Confirm(preview.token)
eq(ok,false);eq(reason,"NO_ONCE_PROTOCOL")
print("PASS distinct point accounts and fail-closed confirmation")

local tests=1
local function test(name, fn) fn();tests=tests+1;print("PASS "..name) end
test("amount format is finite positive and respects roster precision",function()
    local _,_,_,a,s=fixture();local session=service:NewSession(a);session:SetScan(s)
    for _, input in ipairs({"","0","-1","+1","1e3","nan","inf","1,5"," 1","1.001",string.rep("9",400)}) do
        eq(session:Preview(input).error,"INVALID_AMOUNT")
    end
    eq(session:Preview("1.25").total,2.5)
end)
test("unknown and optional-only players are not candidates",function()
    local _,_,_,a,s=fixture();s.players[1].violations={};s.players[2].violations={}
    local session=service:NewSession(a);session:SetScan(s);eq(session:Preview("10").count,1)
end)
test("GUID duplicates, multiple violations and main/alt links charge one account",function()
    local _,_,_,a,s=fixture();s.players[#s.players+1]=s.players[1]
    local session=service:NewSession(a);session:SetScan(s)
    local p=session:Preview("10");eq(p.count,2);eq(p.total,20);eq(#p.targets[1].violations,2)
end)
test("confirmed prior penalty is excluded; unverified status is explicit",function()
    local _,_,done,a,s=fixture();done.main="PENALIZED"
    local session=service:NewSession(a);session:SetScan(s)
    local p=session:Preview("10");eq(p.count,1);eq(p.alreadyCount,1);eq(p.unverifiedCount,1)
end)
test("repeated confirms, scans and profile changes cannot bypass blocking",function()
    local _,_,_,a,s=fixture();local session=service:NewSession(a);session:SetScan(s)
    local p=session:Preview("10");eq(session:Confirm(p.token),false)
    local ok,reason=session:Confirm(p.token);eq(ok,false);eq(reason,"STALE_PREVIEW")
    p=session:Preview("10");session:SetScan(s);ok,reason=session:Confirm(p.token);eq(reason,"STALE_PREVIEW")
    p=session:Preview("10");s.profile="without_dmf";session:SetScan(s);eq(session:Confirm(p.token),false)
    p=session:Preview("10");session:InvalidatePreview();eq(session:Confirm(p.token),false)
end)
test("permissions and context are checked again at confirmation",function()
    local state,accounts,_,a,s=fixture();local session=service:NewSession(a);session:SetScan(s)
    local p=session:Preview("10");state.authorized=false
    local ok,reason=session:Confirm(p.token);eq(ok,false);eq(reason,"NOT_AUTHORIZED")
    state.authorized=true;p=session:Preview("10");state.raidUID="raid-2"
    ok,reason=session:Confirm(p.token);eq(reason,"STALE_PREVIEW")
    p=session:Preview("10");accounts.a={guid="relinked",name="New main"}
    ok,reason=session:Confirm(p.token);eq(reason,"STALE_PREVIEW")
    p=session:Preview("10");state.ledgerHash=2
    ok,reason=session:Confirm(p.token);eq(reason,"STALE_PREVIEW")
end)
test("missing UID or roster, EPGP, closed raids and replay lag are blocked",function()
    for _, c in ipairs({
        {"raidUID",false,"NO_RAID"},{"rosterUID",false,"NOT_DKP"},{"isDKP",false,"NOT_DKP"},
        {"status","FINISHED","RAID_CLOSED"},{"status","STALE","RAID_CLOSED"},
        {"ledgerReady",false,"LEDGER_NOT_READY"},
    }) do
        local state,_,_,a,s=fixture();state[c[1]]=c[2]
        local session=service:NewSession(a);session:SetScan(s);eq(session:Preview("10").error,c[3])
    end
end)
test("two clients, reload and ledger replay cannot produce a second debit",function()
    local state,_,_,a,s=fixture()
    for i=1,4 do
        -- New sessions model different officers/clients and a reload.
        local session=service:NewSession(a);session:SetScan(s)
        state.status=i%2==0 and "IN_PROGRESS" or "CREATED"
        local p=session:Preview("10")
        local ok,reason=session:Confirm(p.token);eq(ok,false);eq(reason,"NO_ONCE_PROTOCOL")
    end
    state.ledgerReady=false
    local session=service:NewSession(a);session:SetScan(s);eq(session:Preview("10").error,"LEDGER_NOT_READY")
end)

test("production CLM adapter excludes locked, missing and wrong-roster identities",function()
    CLM.CONSTANTS={ACL={LEVEL={ASSISTANT=1}},RAID_STATUS={CREATED=0,IN_PROGRESS=1},POINT_TYPE={DKP=0}}
    local writes, authorized = 0,true
    local function profile(guid,main)
        return {guid=guid,main=main,locked=false,GUID=function(self) return self.guid end,
            Main=function(self) return self.main end,IsLocked=function(self) return self.locked end,
            Name=function(self) return self.guid end}
    end
    local alt,main=profile("alt","main"),profile("main","")
    local registry={alt=alt,main=main}
    local membership={alt=true,main=true}
    local roster={UID=function() return 7 end,GetPointType=function() return 0 end,
        GetConfiguration=function() return 2 end,IsProfileInRoster=function(_,guid) return membership[guid] end}
    local raid={UID=function() return "raid-real-adapter" end,Roster=function() return roster end,
        Status=function() return 0 end,Name=function() return "Synthetic raid" end}
    CLM.MODULES.ACL={CheckLevel=function() return authorized end}
    CLM.MODULES.RaidManager={GetRaid=function() return raid end,GetRaidByUid=function() return raid end}
    CLM.MODULES.RosterManager={GetRosterByUid=function() return roster end}
    CLM.MODULES.ProfileManager={GetProfileByGUID=function(_,guid) return registry[guid] end}
    CLM.MODULES.LedgerManager={Lag=function() return 0,0 end,Hash=function() return 1 end,
        IsDisabled=function() return false end,IsInIncoherentState=function() return false end,
        IsTimeTraveling=function() return false end,Submit=function() writes=writes+1 end}
    CLM.MODULES.SandboxManager={IsSandbox=function() return false end}
    CLM.MODULES.PointManager={UpdatePoints=function() writes=writes+1 end,UpdateRaidPoints=function() writes=writes+1 end}
    local session=service:NewSession()
    session:SetScan({profile="with_dmf",players={{guid="alt",name="Alt",violations={{kind="MISSING",name="Fengus"}}}}})
    local p=session:Preview("10");eq(p.targets[1].guid,"main");eq(p.unverifiedCount,1)
    eq(session:Confirm(p.token),false)
    alt.locked=true;p=session:Preview("10");eq(p.count,0);eq(p.excluded[1].reason,"LOCKED");alt.locked=false
    main.locked=true;p=session:Preview("10");eq(p.excluded[1].reason,"LOCKED");main.locked=false
    registry.main=nil;p=session:Preview("10");eq(p.excluded[1].reason,"UNRESOLVED_MAIN");registry.main=main
    membership.main=false;p=session:Preview("10");eq(p.excluded[1].reason,"WRONG_ROSTER");membership.main=true
    membership.alt=false;p=session:Preview("10");eq(p.excluded[1].reason,"WRONG_ROSTER");membership.alt=true
    registry.alt=nil;p=session:Preview("10");eq(p.excluded[1].reason,"UNMAPPED");registry.alt=alt
    main.main="another";p=session:Preview("10");eq(p.excluded[1].reason,"UNRESOLVED_MAIN");main.main=""
    p=session:Preview("10");authorized=false
    local ok,reason=session:Confirm(p.token);eq(ok,false);eq(reason,"NOT_AUTHORIZED")
    eq(writes,0)
end)

test("freshly penalized receipt excludes the target at confirmation",function()
    local _,_,done,a,s=fixture();local session=service:NewSession(a);session:SetScan(s)
    local p=session:Preview("10");done.main="PENALIZED"
    local ok,reason=session:Confirm(p.token);eq(ok,false);eq(reason,"STALE_PREVIEW")
end)

print(tests.." penalty tests passed")
