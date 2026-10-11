# World Buff Checker tests

Run from the repository root with Lua 5.1:

```sh
lua tests/world_buff_checker_spec.lua
lua tests/world_buff_gui_spec.lua
```

Alternatively use Python 3 with Lupa 2.6 (its `lupa.lua51` engine):

```sh
python -m pip install --target .release/test-tools lupa==2.6
# Set PYTHONPATH to the absolute .release/test-tools directory.
python tests/run_lua_tests.py
```

No WoW installation, SavedVariables, guild data, network or peer addon is used.
The identities and durations are synthetic fixtures derived from the user's
reported observations. The Warchief regression uses the explicitly reported
3538 seconds. The eight-player case contains five positive Chronoboons and
three unconfirmed observations; the fifth positive unit is invisible.

Tests exercise the real scanner through its public Scan method with a Blizzard
API adapter, and the real GUI against an AceGUI boundary stub. The GUI test
checks manual invocation, profile invalidation, GUID row deduplication and
details. These tests do not certify real-client aura availability, visual
layout, multiplayer behavior or Blizzard timing.

Existing Ledger/Replay, DKP, raid start/end, auction and communication code is
outside this feature's write scope. Compare those paths with the base commit
5a5787752c95a9ad495239ea1732425bea9a1d21 when reviewing the branch.

The targeted correction adds a visible/connected/no-Chronoboon counterexample,
synthetic eight- and ten-member groups, combat-observed Zandalar alias 355365
without storage, and conflicting positive/zero evidence across GUID aliases.
No original diagnostic reports were supplied or replayed. The ten-member
distribution is a constructed regression, not a claim about a real raid.

MISSING still has positive regression coverage for explicit zero slots in an
observed, validated Chronoboon under the accessibility checks. The old
party/solo-empty-list assertion is updated to UNKNOWN to reflect the corrected
policy. GUI tests verify both the title and optional-buff separator use plain
ASCII hyphens, preventing the two reported mojibake strings from returning.

## v1.1 duration and fail-closed penalty previews

Also run:
- lua tests/world_buff_duration_spec.lua
- lua tests/world_buff_penalty_spec.lua

The Python runner and CI include all four test files. Existing v1 tests remain.
Duration cases cover exact thresholds, frozen storage, adequate alternatives,
unknown duration, optional buffs and independently retained evidence states.
Preview cases cover GUID/main-alt grouping, validation and invalidation,
authorization, actual CLM adapter lock/membership checks, confirmed-receipt
exclusion, replay unavailability and independent client/reload sessions.
GUI cases force even a disabled confirmation and assert no point/ledger write.

Production prior-penalty status is UNKNOWN and every booking is blocked.
Injected receipt states test the adapter contract only. The concurrency tests
prove that blocked clients cannot debit, not that an enabled distributed
idempotency protocol exists. Such a protocol is documented but not implemented.
