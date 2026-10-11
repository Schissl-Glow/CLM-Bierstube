# World Buff penalty ledger analysis

Status: design investigation for v1.1; live penalty booking is blocked.
Baseline inspected: `d671c7d24e4d717f0cd0cbe3ca3cd070cde12234`.
Sources: repository code only. No live points operation was executed.

## Decision

The existing `PointManager:UpdatePoints` / `DM` path cannot guarantee one World Buff penalty per stable raid UID and actually charged account across reload, replay, concurrent authorized clients and profile changes. A note, local flag, SavedVariables flag or history search does not make submission atomic. Until a dedicated replay-safe operation exists, the checker may calculate a preview and explain exclusions but must reject every booking attempt, including programmatic calls. Confirmation must not claim success or imply that a debit was made.

This is the explicitly permitted safe fallback, not a completed DKP penalty implementation. An ordinary negative DM would produce a history entry and synchronized debit, but would violate the stronger once-per-raid requirement. Duration warnings and point-free previews can ship independently.

## Verified existing behavior

All paths below are repository-relative; line references are to the baseline.

| Source | Evidence and consequence |
| --- | --- |
| `ClassicLootManager/Modules/Points/PointManager/PointManager.lua:320` | `UpdatePoints(roster, targets, value, reason, action, note, pointChangeType, forceInstant)` validates basic argument types and point system, creates a normal points entry and calls `LedgerManager:Submit` at line 380. It returns no authoritative charged-account receipt. |
| `ClassicLootManager/Modules/Points/PointManager/PointManager.lua:22`, `:360` | Notes are truncated to 32 bytes. A textual idempotency token is neither a schema field nor a reducer condition. |
| `ClassicLootManager/Modules/Points/PointManager/LedgerEntries.lua:22`, `:72`, `:117` | `DM` records roster UID, target list, value, reason, note and spent flag. It has no raid UID or operation key. `DR` has a raid reference but no once-per-account semantics and applies to raid participants as replayed. |
| `ClassicLootManager/Modules/Points/PointManager/PointManager.lua:26` | `update_profile_standings` creates `alreadyApplied = {}` for each ordinary DM. This deduplicates main/alt targets only within that entry. Separate DMs both apply. |
| `ClassicLootManager/Modules/Points/PointManager/PointManager.lua:37`, `:41`, `:51`, `:66` | Target must be in roster and unlocked. The reducer resolves the target's main at replay time and checks resolved account membership. It does not independently check the resolved main's lock. A preview should exclude a locked target or locked main, not rely on this looser legacy behavior. |
| `ClassicLootManager/Modules/Points/PointManager/PointManager.lua:84` | `apply_mutator` adds roster history before target eligibility checks. History presence alone does not prove that a particular account was charged. |
| `ClassicLootManager/Modules/Points/PointManager/PointManager.lua:484` | `UpdatePointsDirectly` is an internal mutation path, not an idempotent operation API; using it from the checker would bypass the needed shared operation semantics. |
| `ClassicLootManager/Modules/Rosters/RosterManager/Roster.lua:264` | `UpdateStandings` rounds values and applies positive hard/weekly caps; negative amounts update current points. A positive compensating DM can be capped and is therefore not a reliable exact reversal. |
| `ClassicLootManager/Modules/Raids/RaidManager/RaidManager.lua:49` | Raid UID is the `Raid.Create` ledger entry's `uuid()`. Use this stable identity, never raid name, scan ID or time. |
| `ClassicLootManager/Modules/Raids/RaidManager/Raid.lua:67`, `:77`, `:98` | `UID()`, `Start()` and `Status()` expose identity/status. CREATED and IN_PROGRESS are distinct eligible lifecycle states; finished/stale must be excluded. |
| `ClassicLootManager/Modules/Raids/RaidManager/RaidManager.lua:242`, `:830` | `GetRaidByUid()` resolves an explicit raid; `GetRaid()` returns the local player's current CLM raid. A dialog must bind the explicit original raid and invalidate on change. |
| `ClassicLootManager/Modules/Profiles/ProfileManager/ProfileManager.lua:135` | Profile-link entries alter main/alt relations during replay, transfer/sum balances and mirror standings. A display character name is not the charged account. Relinking after preview can change the account. |
| `ClassicLootManager/Modules/Ledger/LedgerManager/LedgerManager.lua:44`, `:370` | Ledger authorization uses `ACL:CheckLevel(ASSISTANT, sender)`. `Submit` appends/transmits; it does not conditionally reserve a raid/account key. |
| `ClassicLootManager/Libs/LibEventSourcing/source/LedgerFactory.lua:74` | `submitEntry` authorizes, calls `StateManager:addEvent`, then transmits to guild and whisper targets. Two authorized clients can independently create different entries before seeing each other. |
| `ClassicLootManager/Libs/LibEventSourcing/source/LogEntry.lua:74`, `:158`, `:166` | Entry identity/order uses timestamp, counter, realm and creator. Unique insertion deduplicates an identical ledger event, not two semantically equivalent penalties. |
| `ClassicLootManager/Libs/LibEventSourcing/source/StateManager.lua:90`, `:368` | Out-of-order insertion can restart replay. All future reservation/debit/reversal state must rebuild in deterministic ledger order and reset on restart. |
| `ClassicLootManager/Libs/LibEventSourcing/source/StateManager.lua:48`, `:202`, `:435` | IGN entries suppress the referenced event handler. Ignoring a winning penalty would remove a naive reducer reservation and could activate a formerly suppressed duplicate on replay. |
| `ClassicLootManager/Modules/GUI/UnifiedGUI_History.lua:497`; `ClassicLootManager/Modules/GUI/UnifiedGUI_Audit.lua:822` | Existing history/audit removal calls `LedgerManager:Remove`. A future specialized penalty must define compatible undo semantics, not inherit this accidentally. |
| `ClassicLootManager/Libs/LibEventSourcing/source/StateManager.lua:227` | Unknown entry classes throw during hydration. A new class is not safe to broadcast to older clients without a compatibility plan. |
| `ClassicLootManager/Libs/LibEventSourcing/source/LogEntry.lua:128`; `ClassicLootManager/Libs/LibEventSourcing/source/StateManager.lua:66` | Current state checksum follows event identity, including ignored entries. Matching ledger hashes alone do not verify matching charged balances or new reducer semantics. |

## Concrete failure example

Managers A and B both preview the same raid/account with no known penalty. A submits DM-A and B submits DM-B before synchronization. Each DM has a distinct event UUID. After synchronization both replay in canonical order. `alreadyApplied` is fresh for each entry, so both debit. A pre-submit `GetData()` search, forced catchup, disabled button or synchronous local pending flag does not exclude this race. `IsInSync()` also cannot prevent a simultaneous new write.

The same failure exists if a reconnecting client lacks the other client's entry. Keeping only a local marker fails after reload on another client; keeping only a text marker in notes does not change legacy reducers. Scanning only recent history also loses older raids and may confuse history creation with actual debit.

## Safe v1.1 integration boundary

The checker can show a frozen proposal: explicit raid UID and roster UID, active requirement profile, settings/revision, scan timestamp, checked character GUID, resolved charged account GUID, evidence statuses, per-buff violations and one fixed, rounded debit per charged account. Collapse main/alt rows to one account before totals and explicitly show which characters led to that account's proposal. Unknown or stale evidence is never a debit reason. Exclude non-DKP rosters, absent/locked profiles and unresolved accounts.

Before confirmation, repeat ACL and live context validation: eligible raid status; same raid/roster/profile/settings; same actual account mapping; fresh scan; initialized enabled coherent ledger without replay/sync lag, sandbox or time travel. These checks prevent stale local decisions but do not solve distributed idempotency. Consequently the service must still return a stable booking-blocked result and never call a points/ledger mutation method. A button being disabled is insufficient protection by itself.

## Future replay-safe design (requires a separately approved core change)

1. **Typed operation.** Introduce a versioned penalty command carrying stable raid UID, roster UID, immutable charged account identity, observed character identities, exact amount, reason/detail breakdown and evidence/settings revision. Keep the operation key independent of the buff requirement profile and settings: `(raidUID, chargedAccountID)`, with guild/ledger namespace implicit and roster UID checked against that raid. A new scan/profile or a different submitting manager must not create another key for the same account.
2. **Account identity contract.** Freeze the account charged at acceptance, never silently re-resolve the displayed alt to a new account during replay. Define behavior for relink, unlink, lock, removal/recreation and transfers. Current main GUIDs are not a durable account abstraction across merges/splits; a durable pool identity/lineage model or an explicit policy blocking penalties after an ambiguous transition is required. The exact once-per-account claim must be limited to that approved identity contract. Preview and reducer both verify membership and effective lock; no key is consumed for a non-applied invalid target.
3. **Atomic reducer.** A dedicated deterministic reducer validates the operation and performs reservation, balance mutation and successful history creation as one state transition. For each key, the first valid candidate in canonical ledger order wins; all further candidates become explicit duplicates without a second debit. The receipt records the actual charged account, amount and winning event. A reducer must not emit another DM or transmit from replay. Reuse points arithmetic through an approved internal seam, not a second ledger append. Rebuild the operation index with ledger replay, sandbox and time travel.
4. **Concurrency semantics.** Canonical first-winner order gives convergent at-most-one debit after all entries arrive; it does not provide instantaneous globally final confirmation while peers are partitioned. An earlier arriving-late candidate can replace the provisional winner on replay. If immediate irrevocable exactly-once acceptance is required, an authoritative sequencer/acknowledgement protocol with fail-closed unavailability is necessary. The current peer ledger and `IsInSync()` cannot offer that promise. The UI must distinguish pending/local proposal from replayed, converged receipt.
5. **Undo and IGN.** Define a typed reversal referencing the operation key and winning event; preserve a consumed-key tombstone so undo cannot promote a duplicate or permit a second penalty. Do not implement reversal as ordinary capped positive DM. Decide whether a future explicitly authorized reapplication has a new operation generation; v1.1's once-per-raid rule permits none. Legacy IGN currently suppresses the handler, so a handler-only index cannot preserve this invariant. All relevant clients need a structural operation index/undo policy that survives IGN and is consistent with time-travel scope, or must reject IGN of penalty operations at the ledger protocol boundary and offer typed reversal. Merely hiding the remove button does not cover old clients, remote IGN, nested IGN or raw audit paths. This remains a release blocker until implemented and tested.
6. **Compatibility.** Old clients either fail on a new event class or, if the change were hidden inside DM, apply all duplicates because they lack the reducer. Do not dual-write a WBP event plus DM, which introduces partial-state and double-debit windows. Require a versioned ledger feature/migration protocol and a tested guild-wide compatibility policy, including offline clients returning later. A list of currently online versions is insufficient to guarantee offline compatibility. Block emission until the migration/compatibility conditions are met.
7. **History and access.** Show accepted/reversed/duplicate/invalid states distinctly; only accepted debit transitions appear as charged points. Store enough immutable detail for human audit, independent of truncated notes. Validate caller ACL on submission and the approved trust model on receipt; preserve actual submitting identity. Existing ASSISTANT-ledger authorization does not imply exclusive authority. Do not activate the development ACL override in packaged builds.

## Required proof before enabling booking

- Two independent authorized clients, same/different proposed amounts, reversed arrival order, equal timestamps and offline reconnection: one final debit and the same winner/account/history on all clients.
- Repeated clicks, new scans, requirement-profile/settings changes and reload/replay: no second debit for an accepted key.
- Main plus multiple alts in one scan; relink/unlink/lock/removal before and after confirmation; unresolved main and membership mismatch: deterministic exclusion or approved account policy, no silent debit to another pool.
- Restart, out-of-order insertion, sandbox apply/discard, time travel and full synchronization: identical balances, account receipts and accepted/duplicate/reversal state, not merely identical event hashes.
- Partial failure before/after reservation and history mutation: no orphan reservation, untracked debit or duplicate history.
- IGN winner, IGN duplicate, IGN reversal, nested IGN and subsequent replay; typed reversal repeated and across relinking; capped positive balances: no duplicate promotion and exact approved undo behavior.
- Old and new client combinations, including offline old clients and unsupported schema versions: safe rejection before emission rather than broken replay or differing balances.
- Unknown/stale aura evidence, zero amounts, decimal rounding, EPGP, unauthorized callers and unsupported lifecycle states: no points writes.

No such future ledger protocol or points-core modification is implemented by this analysis. Live booking remains blocked.
