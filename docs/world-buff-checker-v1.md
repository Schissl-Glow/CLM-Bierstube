# Raid World Buff Checker v1

Development basis: CLM v5.7.8 + Batch 500, commit
`5a5787752c95a9ad495239ea1732425bea9a1d21`.
This feature is a manually invoked Classic Hardcore test tool.
Its source catalog and evidence are in [world-buff-checker-references.md](world-buff-checker-references.md).

## Profiles and evidence

Both profiles require Dragonslayer, Zandalar, Songflower, Fengus, Mol'dar and
Slip'kik. **With DMF** additionally requires any of the eight Sayge variants.
**Without DMF** marks DMF NOT_REQUIRED. Warchief is always optional; its active
and stored observations still appear in details. The user's follow-up
positively validates its stored duration in points[5] (3538 seconds / 59m).
That observation does not make it a required buff.

For each requirement: ACTIVE has precedence over STORED, followed by MISSING
only when absence is trustworthy, otherwise UNKNOWN. Optional entries have
status NOT_REQUIRED and retain a separate observed state in details. A buff
present both active and stored counts once as ACTIVE; both timers are shown.

Stored durations come directly from validated Chronoboon points and remain
frozen. Active timers show their remaining time **at the scan**, without a
background countdown. Opening the window never refreshes data. Changing the
profile clears the old result and requires another manual scan.

The positional Chronoboon decoder is enabled only on Hardcore 1.15.9/build
70003. Other builds preserve active observations; an observed Chronoboon with
unconfirmed schema cannot prove an individual stored buff present or absent.
Each field is validated independently. Missing fields never become zero.

Visibility does not gate enumeration or positive observations. Offline,
invisible, malformed, interrupted, identity-changing or bounded scans cannot
establish absence. Even a fully readable invisible Chronoboon only supplies
positive evidence; unseen requirements stay UNKNOWN without a reliable
negative observation. A 255-index safety bound is not a Blizzard aura limit.

### Conservative MISSING rule

Neither visibility nor reaching nil at the end of the indexed aura list proves
that an unobserved Chronoboon or world buff is absent. Therefore a player with
no observed Chronoboon has UNKNOWN for every unobserved requirement, including
the local player. Concrete active buffs still have priority; Zandalar alias
355365 is accepted without a Chronoboon and during combat observations.

MISSING requires all of the following for that individual buff:
- No positive active or stored observation on any token of the same GUID.
- A stable GUID, connection and visibility before/after uninterrupted indexed
  enumeration, ending normally before the safety bound.
- An observed Chronoboon decoded using the validated 1.15.9/70003 schema.
- An explicit numeric zero in that buff's slot in every observed Chronoboon.

This is a deliberately conservative v1 trust policy, not a Blizzard guarantee
that visibility makes every remote aura list authoritative. A missing or
malformed slot, an unconfirmed schema, or unobservable data remains UNKNOWN.
Positive evidence from an incomplete or invisible unit is retained.

There are no original eight-/ten-player diagnostic reports available for this
correction, as clarified by the user. Regression scenarios are synthetic and
based on the supplied observations; they are not replays of captured reports.
The combat Zandalar 355365 observation is user-provided evidence.

Overall status: known missing requirements => MISSING; otherwise unresolved
requirements => UNKNOWN; otherwise stored requirements => READY_STORED;
otherwise READY_ACTIVE. READY_STORED means the buffs still need releasing from
the Chronoboon before use.

## Architecture and scope

WorldBuffChecker is an on-demand CLM module with a small Blizzard API adapter.
It checks player plus raid1..raid40, or player plus party1..party4, and combines
observations by GUID. The GUI uses a separate AceGUI Window and the existing
CLMLibScrollingTable widget, opened from the Raids tab without officer-only
permissions. It scans the current Blizzard group, independent of a CLM raid
record. Only the observer needs CLM.

There is no event/timer subscription, SavedVariables schema, addon messaging,
Ledger entry, raid-start snapshot or modification of point/auction/raid logic.
Results are transient. Unidentifiable unit tokens are skipped with an explicit
summary count.

## First Ingame acceptance

1. Back up SavedVariables before testing and use a controlled Hardcore session.
   Install a correctly packaged test build of this branch, including external
   libraries and release filtering; do not copy raw development source over a
   live addon. The existing Batch500-only ZIP does not contain this feature.
2. Reload WoW. Open CLM and select the **Raids** tab. No CLM raid needs starting.
3. Click **World Buff Checker**. The window initially has no scan results.
4. Select **Mit DMF** or **Ohne DMF**, then click **Raid prüfen**.
5. Check one row per player, the four requirement counts and overall status.
   Click a row for all eight buff groups. Green ACTIVE and blue STORED must be
   distinguishable. Warchief remains optional even when stored.
6. Reproduce the eight-player case: five positive Chronoboons, including the
   invisible fifth player. The three unconfirmed players must not be labelled
   safely missing solely because no Chronoboon was observed.
7. Check Warchief 3538 seconds (58:58), DMF 23768/23769, zero/missing fields,
   active plus stored buffs, offline/distant members and the player/raid1 alias.
8. Change the profile: results must clear without scanning. Click Raid prüfen
   again to refresh. Close/reopen the window and verify the displayed result is
   still the last manual snapshot.
9. Verify normal CLM navigation, point display, auctions and the existing
   Batch500 replay diagnostic in a controlled test. Do not create a production
   raid-start snapshot as part of this feature.

Automated checks and fixture provenance: [../tests/README.md](../tests/README.md).
Real UI layout, exact API behavior at distance/loading transitions and all
spell alias/DMF variant occurrences remain Ingame acceptance items.
