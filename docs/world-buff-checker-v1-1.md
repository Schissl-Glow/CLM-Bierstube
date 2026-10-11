# World Buff Checker v1.1 TEST

Base: Ingame-confirmed v1 at d671c7d24e4d717f0cd0cbe3ca3cd070cde12234.
The existing two fixed profiles, optional Warchief and conservative evidence
classification remain. v1.1 adds duration warnings and a read-only DKP penalty
preview. **Live booking is blocked. This is not an enabled DKP penalty system.**

## Duration assessment

Dragonslayer, Zandalar, Fengus, Mol'dar, Slip'kik and DMF warn strictly below
6600 seconds (110 minutes). Songflower and optional Warchief warn strictly
below 3000 seconds (50 minutes). The exact boundary is sufficient.

ACTIVE/STORED/MISSING/UNKNOWN/NOT_REQUIRED remain evidence states. A separate
durationStatus is SUFFICIENT, TOO_SHORT, UNKNOWN or NOT_OBSERVED. A known
sufficient active or stored observation wins. If an observed alternative has
unknown duration and no known sufficient alternative exists, the group stays
duration-UNKNOWN and cannot be penalized just for time. Unobserved potential
alternatives do not invent positive evidence.

Active remaining seconds are computed at scan. Stored seconds are frozen.
When aliases expose multiple observations, retain the longest known duration
and unknown-alternative evidence. No timer or background scan is added.

A candidate has at least one required MISSING or reliably TOO_SHORT group.
Unknown evidence/duration and optional groups alone do not qualify. Multiple
violations and main/alt characters map to one potential debit per point
account, with the same fixed amount. The profile is not an idempotency key.

## Preview and authorization

The field accepts a finite positive decimal amount within the roster's
effective precision. Scientific notation, commas, signs, zero, nonfinite and
overprecision input are rejected. Totals are rounded to the roster precision.

The production adapter resolves the observer's current CLM raid by stable UID
and verifies the raid/roster registry identities. CREATED and IN_PROGRESS are
allowed; missing/closed raids, non-DKP rosters, replay lag, sandbox and time
travel block a preview. Both the observed character and resolved main account
must belong to the DKP roster and be unlocked. Missing or chained main links
are excluded rather than guessed. Existing ASSISTANT point permission gates
the controls and is checked by the service at preview and confirmation.

The dialog lists potential accounts, observed characters, concrete violations,
amount per account, total and exclusions. Its confirmation explicitly names
the total but is disabled. New scans, profile changes, amount edits and closing
the dialog invalidate its token. A forced callback still rechecks context and
fails with NO_ONCE_PROTOCOL; no adapter or UI flag can enable a debit.

## Once-per-raid rule and history

Regular DM entries have no shared raid/account key, and their main/alt
deduplication only applies within one entry. History is written before every
target's effective mutation, so it is not a charged-account receipt. The
production adapter consequently reports prior-penalty state as UNKNOWN, not
CLEAR. The confirmed-prior-penalties count must not be read as proof that all
other accounts are uncharged. Exclusion of an authoritative prior receipt is
covered at the adapter contract in tests; the legacy live adapter has no such
receipt source.

Repeated clicks, profile changes, reloads, other officers, concurrent clients
and replay cannot cause a second penalty in this build because **no penalty
can be submitted at all**. No local or SavedVariables once-flag is introduced.
Tests prove fail-closed behavior, not distributed acceptance of real debits.

No points history entries are created and nothing needs reversing from this
build. A future operation needs accepted/duplicate/reversed receipts and a
typed reversal preserving a consumed-key tombstone. Normal positive DM may be
capped; generic IGN may promote a duplicate. Neither is a safe generic undo
for the proposed operation. Full source evidence and future protocol design:
[world-buff-penalty-ledger-analysis.md](world-buff-penalty-ledger-analysis.md).

## Ingame acceptance

1. Back up the addon and SavedVariables; install the complete v1.1 TEST ZIP in
   a controlled Hardcore test environment. Keep the official packaged libraries
   and release filtering. Do not use raw repository files as a live package.
2. Open CLM > Raids > World Buff Checker. Choose either fixed profile and scan.
3. Inspect yellow warning counts and detail rows around 110:00/109:59 and
   50:00/49:59. Active/stored evidence must stay distinguishable. Stored timers
   must stay unchanged between scans; an adequate alternative must suppress a
   short-duration penalty. Optional Warchief never contributes to the debit.
4. With authorized point permissions and an unambiguous current test CLM raid
   in CREATED or IN_PROGRESS plus a DKP roster, enter an amount and click
   **DKP abziehen**. Inspect the preview, account deduplication, violations,
   total, exclusions and unverified prior-penalty status.
5. Confirm that the final confirmation is disabled and the reason is shown.
   There must be no new points history, ledger penalty or changed DKP balance.
6. Change amount/profile or scan again; the old dialog must close and its token
   must become unusable. Test unauthorized access, locked profiles, missing
   roster, EPGP, finished/stale raids and main/alt links.
7. Repeat with two officers and reload. These checks must remain read-only.
   Do not attempt manual production penalties as a workaround for the block.

v1.1 warning/preview layout and real-client behavior still require Ingame
acceptance. Enabling booking requires a separately approved ledger protocol
implementation, compatibility/undo tests and a further Ingame acceptance.
