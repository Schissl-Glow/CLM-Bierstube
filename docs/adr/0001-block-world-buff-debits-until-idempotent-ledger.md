# Block World Buff debits until the ledger has an idempotent operation

The normal DM entry has no raid/account operation key, so concurrent authorized
clients can both debit the same account. v1.1 therefore implements duration
assessment and read-only penalty previews while every confirmation fails
closed, including programmatic calls. This follows the user's explicit fallback
and the prohibition on production booking before separate Ingame acceptance.

A future typed reducer needs a stable charged-account identity, replayed
operation receipts, duplicate suppression, reversal tombstones surviving IGN,
and a mixed-client compatibility policy. Local flags, history notes and a GUI
confirmation cannot provide those guarantees. See
[the ledger analysis](../world-buff-penalty-ledger-analysis.md).
