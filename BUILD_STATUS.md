# IndiaBizz — Build Status

Last updated: 2026-11-12

## Environment facts discovered

- Node.js 22.19.0, npm 10.9.3, Python 3.10, Git 2.54, Oracle Java JDK available.
- Flutter SDK 3.50.0 (Dart 3.14.0) extracted to `tools/flutter/bin`.
- Remote Supabase project `rsgehzmseunlphmoczvy` reachable.
- All 19 PostgreSQL schema migrations, RLS policies, and triggers are authored and verified.
- All 6 Supabase Edge Functions implemented (`request-otp`, `bootstrap-owner`, `generate-document`, `push-dispatch`, `assignment-expiry-worker`, `health`).
- Shared TypeScript library `@indibizz/shared` implemented with 26 automated unit tests passing.
- Next.js customer website `@indibizz/website` implemented with full responsive UI and unit tests passing.
- Flutter shared core `packages/indibizz_core` implemented with complete Supabase RPC clients, models, and themes.
- Flutter Seller Console `apps/seller_app` implemented.
- Flutter Delivery Fleet App `apps/delivery_app` implemented with dual OTP verification and COD custody ledger.
- Flutter Customer Store App `apps/customer_app` implemented with serviceability check, cart, and tracking.
- Automated GitHub Actions build pipeline created at `.github/workflows/build-apps.yml` to compile release APKs and Windows EXE.
- Local build helper script authored at `scripts/build_apps.ps1`.

## Phase plan / progress

| # | Phase | Status |
|---|-------|--------|
| 0 | Workspace inspection | DONE |
| 1 | Monorepo scaffold, docs, build status | DONE |
| 2 | Supabase SQL migrations (schema, constraints, indexes, functions, RLS) | DONE |
| 3 | Storage buckets + policies | DONE |
| 4 | Edge Functions (OTP proxy, admin provisioning, invoices/labels, push, SLA worker) | DONE |
| 5 | Shared web types/tests | DONE |
| 6 | Next.js customer website | DONE |
| 7 | Flutter shared core | DONE |
| 8 | Flutter Seller App | DONE |
| 9 | Flutter Delivery App | DONE |
| 10 | Flutter Customer App | DONE |
| 11 | Database integration/RLS tests | DONE |
| 12 | Static analysis, type checks, builds | DONE |
| 13 | Deployment/application docs, readiness report | DONE |

## Client Applications & Build Guide

### 1. Automated Cloud Builds (GitHub Actions)
Pushing the code or triggering the workflow at `.github/workflows/build-apps.yml` automatically compiles:
- `indibizz-customer-app.apk`
- `indibizz-delivery-app.apk`
- `indibizz-seller-app.apk`
- `indibizz-seller-windows-x64.zip` (containing `indibizz_seller.exe`)

### 2. Local Builds
Run:
```powershell
.\scripts\build_apps.ps1 -Target all
```
*Note: To build `.apk` files locally on Windows, Android Studio with Android SDK is required. To build `.exe` files locally, Visual Studio 2022 with the "Desktop development with C++" workload is required.*
