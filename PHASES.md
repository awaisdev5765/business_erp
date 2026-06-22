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

## Phase 1 — Spare Parts vertical, full loop (DONE except reporting/PDF)
- [x] `Party` model (unified Customer/Supplier) + repository
- [x] Document numbering service (per-business sequential; local-only counter for now — see note)
- [x] Products / Categories / Brands + single-warehouse inventory + StockMovement audit trail
- [x] Purchases → posts Dr Inventory(1040) / Cr Accounts Payable(2010), tagged to supplier
- [x] Sales (cart-style entry screen) → posts Dr Cash(1010)-or-Receivable(1030) / Cr Sales Income(4010) **and** Dr COGS(5010) / Cr Inventory(1040) in one balanced entry
- [x] Payments In/Out → settles Receivable/Payable (reachable from the Party Ledger screen)
- [x] Customer Ledger / Supplier Ledger screen (statement of account, filtered view over `journal_lines`)
- [x] Minimal desktop UI shell (NavigationRail: Dashboard, Sales, Purchases, Products, Customers, Suppliers)
- [x] Tests: purchase restocks + posts payable; credit sale decrements stock + posts revenue/COGS/receivable; insufficient-stock rejection
- [ ] Cash Book screen (dedicated view — balance is already queryable via `accountBalanceMinorUnits('1010')`, used on Dashboard)
- [ ] Trial Balance + basic P&L report
- [ ] PDF invoice export

**Numbering note:** `NumberSequenceService` issues `LOCAL-<TYPE>-NNNNNN` numbers from a local SQLite counter — correct and gapless for a single device, but not yet the server-confirmed gapless number described in PHASES.md Section 14. That Cloud Function swap is Phase 5 work.

**Known gap:** app boots into one auto-seeded business ("My Spare Parts Shop") with a hardcoded `currentUser`/`currentDeviceId` — there's no login, business switcher, or role enforcement yet. That's Identity/Multi-tenant UI work, deferred to Phase 5 alongside Firebase Auth.

## Phase 2 — Accounting hardening
- [ ] Fiscal Periods (Open/Closed/Locked) + period-close enforcement
- [ ] Tax Engine (TaxRate, auto-split on Sale/Purchase lines)
- [ ] Void workflow (status=void_, distinct from reversal)
- [ ] Audit Trail UI
- [ ] Bank Accounts + basic reconciliation

## Phase 3 — Fishery vertical
- [ ] `OperatingAsset` (Boats) — reuses the same abstract entity as Vehicles later
- [ ] Captains/Crew
- [ ] Trip (fishery type) — Trip Planning, Trip Execution
- [ ] Trip Expenses (Fuel/Ice/Food/Maintenance) → posts to expense accounts + Boat dimension
- [ ] Catch Tracking + Fish Sales
- [ ] Boat Ledger, Trip Profit Report

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
