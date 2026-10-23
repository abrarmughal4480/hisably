# Hisably — Architecture

## In short

Hisably is made of small parts, and each part has one job.

- The **screens** only show things and take input.
- The **rules** live in one place, so money is counted the same way everywhere.
- The **database** only saves and loads data.
- Money is always stored as whole paisa (integers), never as decimals,
  so totals are always exact.
- One fast index is built from all entries, so every screen opens instantly.

That is the whole idea. The details are below.

---

A tour of how the app is put together: the modules, the money rules, and
the data structures that keep every screen instant.

## Layers

```
┌────────────────────────────────────────────────────┐
│ UI        screens/ · shell/ · widgets/ · theme/    │
│           (Riverpod consumers, design system)      │
├────────────────────────────────────────────────────┤
│ State     data/providers.dart                      │
│           stream providers + LedgerIndex provider  │
├────────────────────────────────────────────────────┤
│ Domain    data/ledger_index.dart  (pure math)      │
│           data/repository.dart    (write rules)    │
│           data/category_catalog.dart (pure data)   │
├────────────────────────────────────────────────────┤
│ Storage   data/database.dart (Drift / SQLite)     │
│           data/backup_service.dart (JSON)          │
│           data/profile.dart · data/pin_service.dart│
└────────────────────────────────────────────────────┘
```

Each module has one job and a narrow surface. The domain modules
(`ledger_index`, `category_catalog`) import neither Flutter nor the
database driver, so they are unit-tested in isolation.

## Money representation

All amounts are **integer paisa** (1 rupee = 100 paisa), always stored
positive; the *type* of an entry carries its direction. Floats are never
used for money — parsing happens once at the keypad boundary
(`(rupees * 100).round()`), display formats from paisa.

## Sign conventions

Account balance effect per entry type:

| type | account | Khata net (per person) |
|---|---|---|
| income | + | — |
| expense | − | — |
| transfer | − from / + to | — |
| lend | − (cash out) | + (they owe you) |
| borrow | + (cash in) | − (you owe them) |
| lend_repay | + | − |
| borrow_repay | − | + |
| saving | − (into a goal) | — |
| saving_withdraw | + (back from a goal) | — |

Reversed originals and `reversal` rows are excluded from every total.
These rules live in exactly one place — `txBalanceSigns` in
`ledger_index.dart` — shared by the repository (writes) and the index
(reads), so the two can never drift apart.

## Khata rules

- One **net** position per person: lending Rs 500 and borrowing Rs 200
  from the same person nets to Rs 300 receivable.
- Repayments are validated against that net in the repository
  (`addTransaction`, `_validateKhata`) — a repayment can never exceed
  what is outstanding in its direction, including after an edit.
- Savings withdrawals are likewise capped at the goal's saved amount.

## LedgerIndex — the fast path

Screens need many aggregates at once: balance per account, net per
person, saved per goal, income/expense per month, and the user's most
frequent entries. Computing each by rescanning the transaction list is
O(rows × aggregates). Instead:

1. `LedgerIndex.build(all, accounts)` makes **one O(n) pass** over the
   active entries (sorted once, oldest first) and folds everything into
   hash maps: balances, per-person direction totals, goal totals,
   `type|year-month` sums, and `(type, category)` combo counts with
   their latest amount/date.
2. Every read afterwards is an **O(1) map lookup**: `balanceOf`,
   `outstandingOf`, `personTotals`, `goalSavedOf`, `monthSum`,
   `frequent(limit, withinDays)`.
3. Riverpod rebuilds the index once per data change
   (`ledgerIndexProvider`) and shares it across Home, Khata, Savings
   and Reports.

`deltaForAccount` (in the same module) gives the signed effect of one
entry on one account — or on the total, where transfers cancel — which
is what the Reports balance-trend integrates over time buckets.

Underneath, SQLite does its share: `beforeOpen` creates indexes on
`transactions(occurred_at)`, `(account_id)`, `(person_id)` and `(type)`
— the columns every query filters or orders by.

## Writes: repository rules

`LedgerRepository` is the only write path. It enforces:

- amounts > 0; repayments need a person; savings moves need a goal;
- the Khata and savings caps above;
- **edits in place** (`updateTransaction`) for fixing mistakes, with
  caps re-validated against both the old and the new person/goal;
- **reversals** (`reverseTransaction`) as the audit-preserving way to
  undo: the original is flagged `isReversed` and a `reversal` row
  points back at it (`reversesId`). A reversed pair can be deleted
  together (`deleteReversedPair`) since it already counts for nothing;
- first-run seeding and one-time idempotent migrations
  (`migrateCategoryNamesToEnglish`, `assignCategoryIcons`) that upgrade
  existing installs without touching user data or custom categories.

## Storage layout

- `hisably.sqlite` — the Drift database (schema v2) in the app
  documents directory.
- `hisably_profile.json` — the user profile, written with a flush +
  read-back verify (a slow disk can never route a registered user back
  to setup).
- `hisably_pin.hash` — the PIN as a salted SHA-256 hash; biometric
  unlock via `local_auth`. (Platform keystores stalled on some devices;
  the file store is deliberate.)
- Backups are versioned JSON (`backup_service.dart`) containing
  accounts, categories, persons, goals, budgets and transactions;
  older backups restore into newer schemas.

## Startup gate

`main.dart` sequences: animated splash (minimum ~1.5 s) → registration
(3 steps, once) → optional PIN/biometric lock → the shell. Every
storage read on this path is retried or timed out so startup can never
hang; the 12-second safety state offers Retry instead of a wrong
destination.

## Testing

`flutter test` — 29 tests covering the ledger rules and caps, the
backup round-trip, the index math against hand-computed fixtures, the
category catalog/icons, the keypad behaviour, and full-screen widget
tests for the shell, setup wizard, dropdown and reports.
