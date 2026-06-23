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

## Phase 4 — Transport vertical (DONE)
- [x] `OperatingAsset` (Vehicles) — same table as Boats, just `type: vehicle`, exactly as planned in Phase 3
- [x] Drivers (`Party`, `type: driver`) + Driver Assignment — assignment is just `Trip.captainUuid` (the same field Fishery's Captain uses); no separate assignment table needed
- [x] Contracts — new `Contract` registry (company + description + optional rate-per-trip), simple CRUD, optionally referenced by `TripIncome` for traceability. No automatic invoicing/term enforcement — Receivable/Payable tracking for a contract's company is just the existing Customer Ledger, reused as-is
- [x] Trip (`tripType: transport`) — Trip Management reuses the exact same `Trip`/`TripRepository` as Fishery; Trip Income via new `TripIncome` (mirrors `FishSale`'s posting pattern: Dr Cash/Receivable / Cr Trip-Catch Income(4020), no COGS — the trip's cost was already expensed via TripExpense)
- [x] Vehicle expenses (Fuel 5020/Maintenance 5030/Repair 5060/Tyre 5070/Oil 5080) — extended the *same* `TripExpenseCategory` enum and `TripExpense`/`TripExpenseRepository` Fishery built in Phase 3, rather than a parallel Vehicle-specific expense system. Relocated `TripExpense` from `features/fishery/` to `core/activity/` since it's no longer vertical-specific. UI filters which categories it shows via `tripExpenseCategoriesByTripType`.
- [x] Vehicle Ledger (`AssetLedgerScreen`, generalized from `BoatLedgerScreen` — same `LedgerRepository.dimensionStatement()` query, now also showing a lifetime profitability summary card for vehicles) + Vehicle Profitability (`VehicleProfitabilityService` — `TripIncomeRepository.totalForAsset()` minus `TripExpenseRepository.totalForAsset()`, both new queries joining through `trips`) + Driver Performance (`DriverPerformanceService`, same shape grouped by `captainUuid` instead of `assetUuid`)
- [x] Generalized `TripsScreen`/`TripDetailScreen` (moved to `features/activity/`) to be `tripType`-aware instead of duplicating fishery-specific screens: asset/crew labels and dropdowns adapt to Boat/Captain vs Vehicle/Driver, and the trip detail body shows Catch+FishSale sections for fishery or a Trip Income section for transport. Also generalized `BoatsScreen` → `AssetsScreen(assetType)` and `CrewScreen` to accept a configurable role list (reused for both Captains/Crew and Drivers).
- [x] Tests: full two-trip transport flow (fuel/repair/tyre/oil expenses, cash + credit trip income) verifying Vehicle Ledger shows every account touched and Vehicle Profitability/Driver Performance roll up correctly *across* trips, not just within one; credit-trip-income-without-customer rejection

**Architectural payoff realized:** Phase 4 needed zero new tables for OperatingAsset, Party, or Trip, and zero new expense-posting logic for TripExpense — only `TripIncome` and `Contract` were genuinely new, because Transport's revenue shape (a flat trip fee) differs from Fishery's (weight × price). This is the reuse the "unified entity" design in PHASES.md Section 6/12 was meant to produce.

## Phase 5 — Sync + multi-device (PARTIAL — live Firebase project connected)

**Firebase project `buyappsc` is now connected** (`flutterfire configure`
ran for Android/iOS/macOS/Web/Windows — `lib/firebase_options.dart`,
`google-services.json`, `GoogleService-Info.plist` all generated).
`firestore.rules` is deployed (`firebase deploy --only firestore:rules`
succeeded against the live project).

**Decision: free Spark plan, no Cloud Functions.** This changes the
architecture from the original sketch in two ways, both documented at
the top of `firestore.rules`:
1. No custom auth claims (those need the Admin SDK/a Function) — role
   and business access live in a plain `/users/{uid}` Firestore
   document instead, read via `get()` inside rules. Super Admin status
   on that doc is set once by hand in the console.
2. No server-side "debits == credits" validation for JournalEntry
   writes — summing an array isn't expressible in rules without
   Functions. Balance validation stays client-side
   (`LedgerRepository.isBalanced`, already enforced before any write);
   rules add structural/ownership checks only. Real, accepted gap —
   not silently dropped.
3. Atomic document numbering (gapless invoice numbers) will use a
   Firestore client-side `runTransaction` against a counter document
   instead of a Cloud Function — that's a client SDK feature, free-plan
   compatible, not yet implemented since there's no project to run it
   against.

**Built without needing live credentials (DONE):**
- [x] `SyncQueueItem` outbox table + `SyncQueueRepository` — the local
      upload queue every synced entity will go through. Wired into
      `LedgerRepository.postWithin()`/`reverse()`/`void_()` so every
      JournalEntry write enqueues itself in the same transaction as the
      write — opt-in via an optional constructor arg, same pattern as
      `fiscalPeriods`/`auditLog`.
- [x] `ConflictResolutionPolicy` — pure function deciding auto-merge
      (last-write-wins on non-sensitive fields) vs. manual resolution
      (any sensitive field, e.g. credit limit/tax rate, differs) —
      fully unit-tested with constructed field snapshots, no database or
      network needed. `ConflictRecord`/`ConflictRecordRepository`
      persist the "needs manual resolution" cases for the UI queue.
- [x] `SyncStatusScreen` — the Manual Conflict Resolution UI's read
      half: queue depth (pending/failed/synced), unresolved conflicts.
      Nothing populates this yet beyond what local posting enqueues —
      there's no upload worker or remote to actually sync with.
- [x] `firestore.rules` — multi-tenant isolation (Super Admin vs.
      per-business access via `/users/{uid}.businessAccess`), no
      hard-delete rule anywhere, JournalEntry structural validation.
      Written, not deployed — needs `firebase init firestore` against a
      real project first.
- [x] Windows app metadata updated (`Business ERP` display name/window
      title instead of the default `business_erp`); added
      `.github/workflows/windows-build.yml` so the Windows build is
      validated by GitHub's free `windows-latest` CI runner on every
      push — development happens on macOS, which can edit the
      `windows/` platform files but cannot compile them; `flutter build
      windows` only runs on a Windows host. This is the verification
      step that fills that gap, but it only runs once this repo is
      pushed to GitHub (no remote configured yet).
- [x] Tests: 11 new (4 sync-queue, 7 conflict-resolution), 42 total —
      all local, no Firebase needed (still true: these test the pure
      logic, not live Firestore).

**Wired against the live project (DONE):**
- [x] `firebase_core`/`firebase_auth`/`cloud_firestore` added and
      initialized in `main.dart` via `DefaultFirebaseOptions.currentPlatform`
- [x] `UserProfile`/`UserProfileRepository` — Firestore-only model at
      `/users/{uid}` (never local SQL, since this is exactly what
      `firestore.rules` reads via `get()`). The first-ever user to sign
      in is auto-provisioned as Super Admin with `businessAdmin` access
      to the locally-seeded business — matches "one owner, several
      businesses" from the original brief; there's no separate
      invite/onboarding flow for additional team members yet
- [x] `LoginScreen` (email/password sign in + register toggle) and
      `AuthGate` (gates `AppShell` on `FirebaseAuth.authStateChanges()`,
      ensures the `/users/{uid}` profile exists before showing the app)
- [x] `currentUser` now reads the real signed-in user's email instead of
      a hardcoded `'owner'` constant; `currentDeviceId` is still a
      constant — true per-device identifiers are deferred until there
      are actually two devices syncing the same business to test against
- [x] `FirestoreSyncService.uploadPending()` — the real upload half:
      reads `SyncQueueItem`s, fetches each `JournalEntry` (with lines)
      from local SQL, claims a sequence number via a Firestore
      `runTransaction` against `/businesses/{id}/numberSequences/{docType}`
      on first sync (the free-plan substitute for a Cloud Function),
      writes the document to `/businesses/{id}/journalEntries/{uuid}`,
      and marks the queue item synced/failed. Triggered manually via a
      "Sync Now" button on `SyncStatusScreen` — no background/periodic
      worker yet
- [x] `firestore.rules` deployed to `buyappsc`
      (`firebase deploy --only firestore:rules` — compiled and released
      successfully)
- [x] Platform plumbing for live network calls: macOS sandbox
      entitlements (`com.apple.security.network.client`) added to both
      Debug and Release; Android `INTERNET` permission added to
      `AndroidManifest.xml` (the Google Services Gradle plugin was
      already wired by `flutterfire configure`)

**Still pending:**
- [ ] Download/merge sync (pulling another device's changes) — only the
      upload half exists; real multi-device conflict detection needs
      this
- [ ] Background/periodic sync trigger (currently manual "Sync Now" only)
- [ ] Sync for entities other than `JournalEntry` (Party, Product, etc.)
      — same mechanical `SyncQueueRepository.enqueue()` pattern, not yet
      applied to every repository
- [ ] FCM notifications
- [ ] A true multi-device sync QA pass (today's testing is "does it work
      with zero network," which the existing 42 tests already cover —
      proving the upload path against a second real client is next)

## Phase 6 — Fixed Assets/Depreciation, Approval Workflows, Business Switcher (DONE)
Splitting the original "Phase 6+ roadmap" bucket into concrete phases.
Scope chosen for what's highest-value given what already exists:
`OperatingAsset` (boats/vehicles) are literally fixed assets that
depreciate, so a Fixed Asset Register is a natural extension, not a new
concept; Approval Workflows close a real control gap (every Sale/
TripIncome posts immediately, no matter the amount); and a Business
Switcher is overdue — the app has supported multiple businesses
architecturally since Phase 0, but the UI has only ever shown one.
Multi-currency, Payroll, 100k+-row rollup tables, and SaaS expansion
(billing/white-labeling/tenant self-service) are bigger, more speculative
undertakings, deferred to Phase 7+.

- [x] Fixed Asset Register (`FixedAsset`/`FixedAssetRepository`) — links
      to an `OperatingAsset` (boat/vehicle) or stands alone (e.g. shop
      equipment); tracks acquisition cost, date, useful life, salvage
      value; `bookValue()` floors at salvage value
- [x] Straight-line Depreciation Schedule (`DepreciationService`),
      posted monthly: Dr Depreciation Expense(5090) / Cr Accumulated
      Depreciation(1060), tagged to the linked OperatingAsset as the
      journal line's dimension. The *scheduled* last month (by entry
      count vs. `usefulLifeMonths`, not just "remaining < one month's
      amount") absorbs the integer-division rounding remainder — caught
      a real bug here where 100 over 3 months left a phantom 4th month
      because remaining (34) was briefly *larger* than one month's
      amount (33), so the original "cap if remaining is smaller" check
      never fired
- [x] Approval Workflow (`ApprovalThreshold`/`ApprovalThresholdRepository`)
      wired into `SaleRepository`: a credit sale above the business's
      configured threshold is created `pendingApproval` (no stock
      movement, no JournalEntry) until `SaleRepository.approve()` runs.
      Re-validates stock at approval time, not just at creation — a
      pending sale can sit for a while, and another sale may have
      consumed the same stock in the meantime; covered by a test.
      **Not yet applied to TripIncome** — identical mechanical pattern,
      deferred rather than duplicating the same logic twice in one phase
- [x] Business Switcher (`BusinessRepository`, `BusinessSwitcherScreen`,
      `selectedBusinessIdProvider`) — replacing the Phase 0-5 "boots into
      one auto-seeded business" placeholder. Creating a business also
      grants the creating user's Firestore profile access to it
      (`UserProfileRepository.grantAccess`), so it's visible under
      `firestore.rules` once synced
- [x] Super Admin cross-business dashboard (`CrossBusinessDashboardScreen`)
      — read-only rollup (cash position, revenue) across every business
      in the local database, gated on `UserProfile.isSuperAdmin`; never
      commingles each business's actual ledgers
- [x] Fixed Assets and Approvals screens wired into the nav shell
- [x] Tests: 11 new (4 depreciation, 7 approval workflow), 53 total —
      all passing, `flutter analyze` clean

## Phase 7+ — see full roadmap
Multi-currency, Payroll, rollup tables for 100k+ row performance, SaaS
expansion (billing, white-labeling, tenant self-service onboarding).
