# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A ledger-first ERP (Flutter + sqflite, Firebase for sync/backup only) serving three businesses run by one owner: a Spare Parts Shop, a Fishery, and a Transport company. Every module action ultimately creates one `JournalEntry` with balanced `JournalLine` rows — sub-ledgers (Customer, Supplier, Boat, Vehicle, Cash Book) are filtered SQL views over `journal_lines`, never separate tables. **Read `PHASES.md` before making non-trivial changes** — it's the authoritative build log (10 phases, all done) with the actual architectural reasoning, every bug found and fixed, and every deliberate gap/simplification with why it was left that way. This file is a map to get oriented quickly; PHASES.md is the detail.

## Commands

```bash
flutter pub get                 # install dependencies
flutter analyze                 # static analysis — must be clean before considering a change done
flutter test                    # full suite (sqflite_common_ffi-backed, no device/emulator needed)
flutter test test/foo_test.dart # single file
flutter test --plain-name "some test name"   # single test by name
flutter run -d macos            # or -d chrome / -d windows / an attached device
flutter build web                # produces build/web (Firebase Hosting's public dir)
firebase deploy --only hosting   # deploy the web build to project "buyappsc"
```

**Sandboxed-shell gotcha:** `flutter test`/`flutter pub get` can hang indefinitely in network-sandboxed shells — the transitive `sqlite3` package builds its native lib from source via a Dart hooks build step on first run, which needs network access. Symptom: a `dart ... hook.dill` process sitting idle with zero test output. Run with the sandbox disabled for that one command if this happens.

There is no separate lint step beyond `flutter analyze` (config in `analysis_options.yaml`, stock `flutter_lints` with no rule overrides). No CI is configured for analyze/test; `.github/workflows/windows-build.yml` only validates that the Windows platform folder compiles (development happens on macOS, which can edit `windows/` but not build it).

## Architecture

### Layout
- `lib/core/` — domain logic shared across verticals: `accounting/` (the ledger kernel), `party/` (unified Customer/Supplier/Captain/Crew/Driver/Employee), `tenant/` (Business), `identity/` (UserProfile/RBAC), `sync/` (outbox + conflict resolution), `system/` (database, DI providers, audit log, number sequencing), `activity/` (Trip — shared by Fishery & Transport), `asset/` (OperatingAsset — Boats & Vehicles, one table), `transaction/` (Payment, SalaryRecord).
- `lib/features/` — per-vertical UI + repositories: `spare_parts/{inventory,purchases,sales}`, `fishery/`, `transport/`, `accounting/` (reports screens), `payroll/`, `dashboard/`, `identity/` (login/staff management), `tenant/` (business switcher).
- `lib/shared/` — currency formatting, PDF export (`shared/pdf/report_pdf.dart`, `InvoicePdf`), theme/design tokens (`shared/theme/app_theme.dart` — `AppSpacing`/`AppColors`), reusable widgets.
- `test/*_test.dart` — one file per concern (not per-class), named after the behavior under test (`approval_workflow_test.dart`, `void_test.dart`, etc.), all using `sqflite_common_ffi` against a fresh temp-dir SQLite file per test (`setUp`/`tearDown`), no mocking framework.

### The ledger kernel (`lib/core/accounting/`)
`LedgerRepository` is the **only** write path for financial data — every module posts through `post()`/`postWithin()` (the latter for composing with another write, e.g. Sale's JournalEntry + stock movement, in one `db.transaction` since sqflite has no nested transactions). Three terminal operations on a posted entry, each with a distinct meaning — don't conflate them:
- `reverse()` — entry was correct at the time, needs offsetting now (refunds, pricing corrections). Appends a new entry with flipped Dr/Cr; never mutates the original.
- `void_()` — entry should never have counted at all (duplicate, test data). Marks `status=void_`, writes nothing else; every balance/statement query filters `status != void_`.
- Both require an opt-in `AuditLogRepository` to actually log who/what/when/why — without one wired in, both still work, just silently.

`LedgerRepository`'s other constructor args (`fiscalPeriods`, `syncQueue`, `rollups`) are all **optional, opt-in** in the same pattern: a business/test that doesn't wire one in gets Phase-0/1 behavior unchanged. This is why the 85-test suite (none of which construct `LedgerRepository` with every optional arg) still works as the regression suite for later phases — always preserve this pattern when adding a new optional concern rather than making it required.

`accountBalanceMinorUnits()`/`outstandingBalanceMinorUnits()`/`trialBalance()` read from `account_balance_rollups`/`party_balance_rollups` when a `BalanceRollupRepository` is wired in (O(1) instead of scanning all of `journal_lines`); otherwise they fall back to the original scanning SQL. Both paths must always agree — `balance_rollup_test.dart` asserts this explicitly. If you touch posting/void logic, check whether the rollup increment/decrement needs a matching change.

**Multi-tenant isolation is a query-level concern, not just a UI concern.** Account codes are only unique *within* a business (`UNIQUE(business_id, code)`), so any new aggregate query must join through business-scoped `journal_entries` *before* joining to `journal_lines`/`accounts` — joining on `account_code` alone can leak another business's lines for a shared code. This exact bug was caught and fixed in Phase 1 (`reports_test.dart` covers it); don't reintroduce the pattern.

### Unified entities (read this before adding a "new" concept)
The codebase aggressively avoids parallel tables for conceptually-similar things across verticals — check whether what you need already exists before adding a table:
- `Party` — one table for Customer, Supplier, Captain, Crew, Driver, Employee (`PartyType`). Salary eligibility, ledger statements, etc. all work for any type for free.
- `OperatingAsset` — one table for Boats and Vehicles (`OperatingAssetType`), including Fixed Asset Register linkage and depreciation.
- Transport matches the customer's two Excel books: **Company Bills** (`WeightEntry`: date + vehicle + kg + company, no journal) and **Gari Khata** (`VehicleKhataLine`: Date / Tafseel / Kharcha / Jama + running Total Raqam, one sheet per vehicle). Month Hisaab (`MonthlySettlement`) is kg × rate/ton → company receivable + a Jama row on each vehicle's khata. `TripIncome` remains for old rows only.
- `AssetsScreen`/`CrewScreen`/`TripsScreen`/`TripDetailScreen` are generalized, `tripType`/`assetType`-aware screens, not per-vertical duplicates.

### Money, dates, numbering
- All money is **integer minor units** (cents), never floating point. `formatMoney(minorUnits, currencyCode)` in `shared/currency/currency.dart` is the only formatter; `currentCurrencyProvider` resolves the active business's currency.
- Document numbers (`NumberSequenceService`, `lib/core/system/number_sequence_service.dart`) are atomic per `(business_id, doc_type, year)`, formatted `TYPE-YEAR-NNNNNN` (e.g. `SALE-2026-000042`) — the counter resets every January. This is a **local-only** gapless counter (correct for one device); a Firestore-`runTransaction`-based server-confirmed version is the documented next step, not yet built for every doc type.
- Sales/refunds/purchases snapshot unit cost and tax rate **on the line at transaction time** (`SaleLine.unitCostMinorUnits`/`taxRatePercent`), so a later price change never retroactively alters a posted document's COGS or tax.

### State management & DI
Riverpod `FutureProvider`s in `lib/core/system/providers.dart` are the single DI registry — every repository is constructed there from `databaseProvider`, composed the same way (`final x = await ref.watch(yProvider.future)`). When adding a repository, register it here following the existing pattern rather than constructing it ad hoc in a screen. `currentBusinessIdProvider`/`currentBusinessProvider` resolve the active tenant; almost every repository call takes `businessId` explicitly rather than reading it from ambient state.

### Schema migrations (`lib/core/system/database.dart`)
`createSchema()` builds a fresh DB at the latest shape; `migrateSchema()` has one `if (oldVersion < N)` block per version bump, additive only where possible (SQLite `ALTER TABLE` can only add one column at a time with a constant default — no backfill logic needed for those). When a primary key itself needs to change (not just adding a column), the existing pattern is: rename the old table, create the new one via its `createTableSql`, `INSERT ... SELECT` the old data across with a sensible default for the new key column, then drop the renamed table — see the `number_sequences` v4→v5 migration for a worked example. Always bump `_schemaVersion` and add both the `createSchema()` call and the `migrateSchema()` block in the same change — they're meant to never drift apart.

### Cloud restore (web data-loss recovery)
`sqflite_common_ffi_web` (the web SQLite backend) is explicitly experimental and persists to IndexedDB in a way that can lose everything across a closed/reopened browser tab. Because of this, every create-path repository in the app — `Business`, `Purchase`/`Sale`/`Refund`, the whole Fishery vertical (`OperatingAsset`, `Trip`, `TripExpense`, `FishCategory`, `CatchEntry`, `FishSale`), the whole Transport vertical (`Contract`, `TripIncome`, `WeightEntry`, `MonthlySettlement`, `VehicleKhataLine`), Payroll (`SalaryRecord`/`SalaryPayment`), Fixed Assets/Depreciation, Bank Reconciliation (`BankAccount`/`BankStatementLine`), and the shared registries (`Category`/`Brand`/`FiscalPeriod`/`TaxRate`/`ApprovalThreshold`) — enqueues to the same `SyncQueueRepository` outbox `Party`/`Product` originally used (all optional/opt-in constructor args, same pattern as everywhere else). `FirestoreSyncService.restoreFromCloud()` rebuilds a wiped local database from Firestore in dependency order: `Business` row + re-seeded Chart of Accounts, then every domain entity above, then `downloadAndMerge()` for JournalEntries last (since entries reference everything else by uuid). `currentBusinessIdProvider` (`lib/core/system/providers.dart`) calls this exactly once per app session, only when local SQLite has zero `Business` rows.

Most entities reuse one generic pair, `_uploadFlat`/`_downloadFlat` (same table/collection-name + row↔doc field-mapping shape) — only entities with embedded child lines (Sale/Purchase/Refund) or no `uuid` at all (`ApprovalThreshold`, composite-keyed) get bespoke methods. Two correctness traps already hit and fixed here, worth knowing before extending this further:
- `SaleLine.id` is round-tripped explicitly through the Firestore doc (not left to autoincrement) specifically so a restored `RefundLine.saleLineId` still points at the right line — get this wrong and refund-quantity tracking silently breaks after a restore.
- `NumberSequenceService.resyncFromIssuedNumbers()` — the `number_sequences` counter itself is never synced (two devices' raw counters could disagree about the real high-water mark); instead, after every other entity restores, it's recomputed from the document numbers that actually exist locally (`SALE-2026-NNNNNN` etc., parsed back apart), only ever raising `last_number`, never lowering it. Skipping this would mean the first document created on a restored device reissues an already-used number.

`StockMovement` and `AuditLog` are synced too (same `_uploadFlat`/`_downloadFlat` pattern; `AuditLog`'s primary key is `id`, not `uuid`, so it gets a bespoke pair instead of `_uploadFlat`/`_downloadFlat`'s default).

**Data that predates sync coverage for its entity type** (e.g. a business created before this restore system existed at all) has no Firestore doc to recover from by default — `FirestoreSyncService.backfillSyncQueue(businessId)` closes that gap from here forward: it scans every synced table for rows with *no* `sync_queue_items` row at all yet (not pending — never tracked) and enqueues them. `syncAll()` calls it automatically, once per business per app session (`_backfilledThisSession` guard — the table scans aren't cheap enough to run on every 3-minute background tick). This doesn't resurrect data that's already gone with no copy anywhere; it protects whatever's still sitting in local SQLite right now so the *next* storage-loss event doesn't repeat this one. See `test/backfill_sync_test.dart` for the exact scenario (every repository built with no `SyncQueueRepository` at all, mirroring a pre-sync app build).

**Sync triggers, so nothing waits on a manual tap:** on app open, every 3 minutes (`Timer.periodic` in `AppShell`), on every foreground resume, and — via `connectivity_plus`'s `Connectivity().onConnectivityChanged` — the instant the device transitions from offline to online (`AppShell._connectivitySubscription`/`_wasOffline` in `lib/app.dart`). The Sync Status screen's "Sync Now" button still exists for "let me check right now," it's just never the *only* way a reconnect gets noticed.

### Auth/RBAC
One Super Admin (`kSuperAdminEmail`, hardcoded), who sees every business; staff sign in on their own admin-created credentials and only see businesses explicitly granted via `UserProfile.businessAccess`. `firestore.rules` is the actual enforcement for Firestore reads/writes; SQLite-side screens trust `isReadOnlyProvider`/`accessibleBusinessesProvider` for UI gating only. Firebase is on the free Spark plan — no Cloud Functions, which is why several things that would normally be server-side (atomic numbering, push notification sending, balance validation in rules) are deliberately client-side instead; each such spot is commented with why.

### Testing conventions
Almost all logic tests are pure-repository tests against a real (temp-file) SQLite DB — no widget tests, no mocking framework, no live Firebase (sync tests use `fake_cloud_firestore`). Follow the existing `setUp`/`tearDown` boilerplate (seed chart of accounts, construct only the repositories the test needs with the optional args it actually exercises) rather than introducing a new test harness. UI-only changes (nav filtering, RBAC screens) have historically been verified by `flutter analyze` + manual run rather than automated tests, since there's no Firebase/widget-test mocking infrastructure set up yet — match that precedent rather than unilaterally adding one.
