# Build Phases

Ledger-first ERP for three businesses (Spare Parts, Fishery, Transport).
Flutter + sqflite (local-first SQL) + Firebase (sync/backup only, wired in
a later phase). Full architecture detail lives in the project conversation
history; this file tracks build sequencing and status.

Core principle: every module action ultimately creates one `JournalEntry`
with balanced `JournalLine` rows. Sub-ledgers (Customer, Supplier, Boat,
Vehicle, Cash Book) are filtered SQL views over `journal_lines`, not
separate tables.

## Phase 0 — Accounting Kernel (DONE)
- [x] Flutter project scaffolded (`business_erp`, Windows/Android/iOS/Web targets)
- [x] Folder structure: `core/{accounting,tenant,identity,party,asset,activity,transaction,sync,system,rollup}`, `features/`, `shared/`
- [x] `Business` model (tenant)
- [x] `Account` model + seeded Chart of Accounts (5-type: Asset/Liability/Equity/Income/Expense)
- [x] `JournalEntry` + `JournalLine` SQL schema (append-only, integer minor units)
- [x] `LedgerRepository`: `post()`, `reverse()`, `accountBalanceMinorUnits()`
- [x] Tests proving: balanced posting, unbalanced rejection, reversal nets to zero without mutating history

**Local DB note:** switched from Isar to `sqflite` + `sqflite_common_ffi`
(raw SQL) — accounting needs real relational aggregation (SUM/GROUP BY
across journal_lines joined to journal_entries), which is awkward in
Isar's NoSQL query API. Desktop (Windows/macOS/Linux) and `flutter test`
use the FFI database factory; Android/iOS use the native sqflite channel
automatically (see `lib/core/system/database.dart`).

## Phase 1 — Spare Parts vertical, full loop (DONE)
- [x] `Party` model (unified Customer/Supplier) + repository
- [x] Document numbering service (per-business sequential; local-only counter for now — see note)
- [x] Products / Categories / Brands + single-warehouse inventory + StockMovement audit trail
- [x] Purchases → posts Dr Inventory(1040) / Cr Accounts Payable(2010), tagged to supplier
- [x] Sales (cart-style entry screen) → posts Dr Cash(1010)-or-Receivable(1030) / Cr Sales Income(4010) **and** Dr COGS(5010) / Cr Inventory(1040) in one balanced entry
- [x] Payments In/Out → settles Receivable/Payable (reachable from the Party Ledger screen)
- [x] Customer Ledger / Supplier Ledger screen (statement of account, filtered view over `journal_lines`)
- [x] Cash Book screen (same statement pattern, filtered by account 1010 instead of party)
- [x] Trial Balance report (`LedgerRepository.trialBalance()` — one grouped SQL query, all accounts' Dr/Cr/balance)
- [x] Basic P&L report (income earned minus expense spent, derived from trialBalance rows)
- [x] PDF invoice export (`pdf`/`printing` packages — client-side for now; see note)
- [x] Minimal desktop UI shell (NavigationRail: Dashboard, Sales, Purchases, Products, Customers, Suppliers, Cash Book, Trial Balance, P&L)
- [x] Tests: purchase restocks + posts payable; credit sale decrements stock + posts revenue/COGS/receivable; insufficient-stock rejection; trial balance and account balance are business-scoped even when two businesses share an account code

**Multi-tenant bug caught and fixed during Phase 1:** the first draft of `trialBalance()` joined `journal_lines` to `accounts` on `account_code` alone. Account codes are only unique *within* a business, so that join could pull another business's lines for the same code (e.g. two businesses both have "1010"). Fixed by joining through business-scoped `journal_entries` first. Covered by `test/reports_test.dart` — this is exactly the class of bug PHASES.md Section 16 warns about ("multi-tenant isolation has to hold at the query level, not just the UI level").

**PDF export note:** invoice rendering runs client-side via the `pdf`/`printing` packages. PHASES.md Section 17 calls for this to eventually run through a shared Cloud Function template so Desktop/Web/Mobile render identically — that's deferred to Phase 5 alongside the rest of the Firebase wiring.

**Numbering note:** `NumberSequenceService` issues `LOCAL-<TYPE>-NNNNNN` numbers from a local SQLite counter — correct and gapless for a single device, but not yet the server-confirmed gapless number described in PHASES.md Section 14. That Cloud Function swap is Phase 5 work.

**Known gap:** app boots into one auto-seeded business ("My Spare Parts Shop") with a hardcoded `currentUser`/`currentDeviceId` — there's no login, business switcher, or role enforcement yet. That's Identity/Multi-tenant UI work, deferred to Phase 5 alongside Firebase Auth.

## Phase 2 — Accounting hardening (DONE)
- [x] Fiscal Periods (Open/Closed/Locked) + period-close enforcement — `FiscalPeriodRepository.assertOpenForPosting()` runs inside `LedgerRepository.postWithin()`'s transaction; opt-in (a business with no periods configured posts freely, unchanged from Phase 0/1). A reversal's date defaults to "now," so reversing an entry from a since-closed period still works without special-casing.
- [x] Tax Engine (TaxRate registry + per-line tax snapshot on Sale/Purchase, auto-split into account 2020 Tax Payable). Sales: Dr Cash/Receivable tax-inclusive, Cr Sales Income tax-exclusive, Cr Tax Payable (output tax). Purchases: Dr Inventory tax-exclusive, Dr Tax Payable (input tax claim), Cr Accounts Payable tax-inclusive. Both nest through the *same* 2020 control account — a deliberate simplification (see doc comment on `PurchaseRepository`), not full input/output tax reporting.
- [x] Void workflow (`LedgerRepository.void_()`), distinct from reversal: marks `status=void_` and writes nothing else — every balance/statement/trial-balance query already filters `status != void_`, so a voided entry simply stops counting everywhere, no offsetting entry needed. Reachable from the Party Ledger screen with a required reason. Reverse is for "this happened but needs correcting"; Void is for "this should never have counted."
- [x] Audit Trail (`AuditLog` table, opt-in third constructor arg on `LedgerRepository`) — every `void_()`/`reverse()` call logs who/what/when/why. Read-only Audit Trail screen wired into nav.
- [x] Bank Accounts + basic reconciliation — `BankAccount` registry + manually-entered `BankStatementLine`s, tick off cleared lines, compare cleared running balance against a stated statement closing balance. CSV/OFX import and wiring Sales/Payments to post against a *specific* bank account (rather than the generic 1010/1020 GL accounts) are both deferred — see doc comment on `BankAccount`.
- [x] Tests: 27 total across fiscal periods, tax engine, void, audit log, and bank reconciliation — all passing.

**Bug found and fixed mid-Phase-2:** `lib/core/accounting/ledger_repository.dart` was discovered corrupted (large chunks of `postWithin()`/`reverse()` missing — likely an editor/save mishap) partway through this phase. Rebuilt from scratch with the same logic plus the new `void_()` method; `flutter analyze`/`flutter test` confirmed the rebuild was correct.

**Sandbox note:** `flutter test`/`flutter pub get` can hang indefinitely in network-sandboxed shells because the transitive `sqlite3` package now builds its native library from source via a Dart "hooks" build step on first run, instead of shipping a prebuilt binary — that build step needs network access it doesn't get by default in this environment. Symptom: a `dart ... hook.dill` process sitting at the same elapsed time with zero test output. Fix: run with the sandbox disabled for that one command.

## Phase 3 — Fishery vertical (DONE)
- [x] `OperatingAsset` (Boats) — unified entity (`type: boat`), reused as-is for Vehicles in Phase 4 (just a new enum value, no new table)
- [x] Captains/Crew — reused `Party` (`type: captain/crew`), no new table; no ledger/payment actions on the Crew screen since salary tracking is a later Payroll phase, not Phase 3
- [x] Trip (`tripType: fishery`) — Planning (create, status `planned`) → Execution (`start()` → `inProgress`, `complete()` → `completed` + `endDate`)
- [x] Trip Expenses (Fuel 5020/Ice 5040/Food 5045/Maintenance 5030) → Dr expense account / Cr Cash(1010), both lines tagged `dimensionUuid = boat.uuid`
- [x] Catch Tracking (`CatchEntry` — no accounting posting, just pre-sale inventory-of-catch) + Fish Sales (`FishSale` → Dr Cash/Receivable / Cr Trip-Catch Income(4020), tagged to the boat dimension and, for credit sales, the customer party). No COGS posting for fish sales — the catch's cost was already expensed via TripExpense, so Trip Profit is revenue minus expenses directly, not a per-unit cost calc.
- [x] Boat Ledger (`LedgerRepository.dimensionStatement()` — new query, every journal line tagged with one dimension across *all* accounts, the dimension-axis counterpart to `accountStatement()`'s account-axis view) + Trip Profit Report (`TripProfitService` — `FishSaleRepository.totalForTrip()` minus `TripExpenseRepository.totalForTrip()`)
- [x] UI: Boats list, Crew list, Trips list + Trip Detail (status actions, expense/catch/fish-sale entry inline, live profit summary), Boat Ledger — all wired into the same NavigationRail as Spare Parts (see "Known gap" below)
- [x] Tests: full trip lifecycle (plan→start→expense→catch→sell→complete) verifying Boat Ledger shows every account touched and Trip Profit nets correctly; credit-fish-sale-without-customer rejection

**Known gap carried over:** the NavigationRail now lists Spare Parts and Fishery screens side by side with no business-type-aware filtering — there's no concept yet of "this nav item only shows for a Fishery business." That's deferred to Phase 5/Identity work alongside the business switcher itself (see Phase 1's "Known gap" note).

## Phase 4 — Transport vertical
- [ ] `OperatingAsset` (Vehicles)
- [ ] Drivers + Driver Assignment
- [ ] Contracts
- [ ] Trip (transport type) — Trip Management, Trip Income
- [ ] Vehicle expenses (Fuel/Maintenance/Repair/Tyres/Oil)
- [ ] Vehicle Ledger, Vehicle Profitability, Driver Performance

## Phase 5 — Sync + multi-device
- [ ] Wire Firebase (Auth, Firestore, Cloud Functions, FCM) per the
      sync architecture: Isar/SQL local-first, Firestore = auth + backup +
      sync + notifications only, never the live query target
- [ ] Cloud Function: atomic sequence number issuance, server-side balance validation
- [ ] Upload/download sync engine + Sync Queue + retry/backoff
- [ ] Manual Conflict Resolution UI for financial master-data conflicts
- [ ] Multi-tenant Firestore Security Rules
- [ ] Windows packaging/installer
- [ ] Full offline QA pass across all three verticals

## Phase 6+ — see full roadmap
Multi-currency, Fixed Assets/Depreciation, Approval workflows, Payroll,
rollup tables for 100k+ row performance, Super Admin cross-business
dashboard, SaaS expansion (billing, white-labeling, tenant self-service).
