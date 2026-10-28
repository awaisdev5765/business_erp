# Business ERP

Business ERP is a Flutter-based, ledger-first ERP for small and mid-sized businesses. It combines double-entry accounting with inventory, sales, purchasing, parties, cash management, reporting, payroll, and operations workflows for spare-parts, fishery, and transport businesses.

The app is local-first: transactional screens use SQLite for fast offline work, while Firebase provides authentication, backup, and synchronization capabilities.

## What it includes

- Double-entry general ledger with balanced journal posting and reversals
- Multi-business/tenant data model with role-aware access
- Spare-parts inventory, brands, categories, purchasing, sales, stock movements, and refunds
- Customer and supplier ledgers, payments, cash book, bank reconciliation, and audit trail
- Trial balance, profit and loss, sales, purchase, stock, receivables, payables, and closing reports
- Tax rates, fiscal periods, approvals, fixed assets, depreciation, and retained earnings
- Fishery operations: boats, crew, trips, catch tracking, fish sales, and trip profitability
- Transport operations: vehicles, drivers, contracts, trip income, expenses, settlements, and vehicle profitability
- PDF invoices and reports, data backup/restore, WhatsApp support links, and offline status indicators
- Flutter targets for Android, iOS, macOS, Windows, Linux, and Web
- Firebase Authentication, Firestore sync rules, push notifications, and conflict/sync queue infrastructure

## Architecture

```text
Flutter UI (Riverpod)
        │
        ├── Feature screens and workflows
        ├── Repositories and accounting services
        ├── Local SQLite database (primary transactional store)
        └── Firebase Auth / Firestore (sync and backup layer)
```

Every business action that changes money ultimately posts a balanced journal entry. Customer, supplier, cash, boat, and vehicle statements are filtered views over the journal rather than separate accounting systems.

## Requirements

- Flutter SDK compatible with Dart `^3.11.1`
- Android Studio or Xcode, depending on the target platform
- Firebase project for authentication, Firestore, and optional messaging/sync
- CocoaPods for iOS/macOS development

## Getting started

```bash
git clone https://github.com/awaisdev5765/business_erp.git
cd business_erp
flutter pub get
flutter analyze
flutter test
flutter run
```

For a specific target:

```bash
flutter run -d chrome       # Web
flutter run -d macos       # macOS
flutter run -d windows     # Windows
flutter run -d linux       # Linux
```

## Firebase setup

For a new deployment, configure Firebase for every target with FlutterFire and review the security rules before deploying:

```bash
flutterfire configure
firebase deploy --only firestore:rules,firestore:indexes
```

Never commit service-account credentials, private keys, admin SDK secrets, or production exports. Firebase client configuration is not a substitute for Firestore security rules; keep tenant and role checks enabled.

## Project layout

```text
lib/core/         Accounting kernel, sync, tenancy, identity, parties, assets
lib/data/         SQLite database, DAOs, models, repositories, Firebase adapters
lib/features/     Dashboard, sales, purchases, inventory, reports, payroll, operations
lib/shared/       Theme, currency, widgets, PDF/report helpers, utilities
test/             Accounting, repository, sync, and workflow tests
web/              Web entry point, manifest, and SQLite worker assets
PHASES.md         Architecture roadmap and completed phase notes
```

## Testing and quality

```bash
flutter format --set-exit-if-changed .
flutter analyze
flutter test
```

The Windows build workflow in `.github/workflows/windows-build.yml` validates the Windows target on GitHub Actions, since Windows builds cannot be compiled locally on macOS.

## Data and privacy

Business ledgers, customer records, payroll data, and credentials can be sensitive. Use test data in development, restrict Firebase access by business and role, and never commit local database exports or customer spreadsheets. Review `firestore.rules` and the in-app data-wipe/backup flows before deploying to production.

## Roadmap

Completed and planned work is tracked in [PHASES.md](PHASES.md), including accounting hardening, vertical workflows, Firebase sync, conflict resolution, and platform delivery.

## License

No open-source license has been published yet. All rights are reserved unless a license file is added to this repository.
