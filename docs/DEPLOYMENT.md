# IndiaBizz Deployment & Setup Guide

This guide details how to configure Supabase, apply database migrations, deploy Edge Functions, and build production client artifacts.

---

## 1. Supabase Project Configuration

1. **Enable Phone Authentication**:
   - In Supabase Dashboard: Go to **Authentication** -> **Providers** -> **Phone**.
   - Toggle **Enable Phone Provider**.
   - Configure **Twilio** (or custom SMS provider) with Account SID, Auth Token, and Message Service SID.
   - Configure the SMS template: `Your IndiaBizz verification code is: {{ .Code }}`.

2. **Database Migrations**:
   Run the following command using Supabase CLI with your database connection string or access token:
   ```bash
   # Link project
   npx supabase link --project-ref <PROJECT_REF>

   # Push all schema migrations
   npx supabase db push
   ```
   Or apply the SQL migration scripts sequentially in `supabase/migrations/` using `psql`:
   ```bash
   psql "$SUPABASE_DB_URL" -f supabase/migrations/20260101000000_foundation.sql
   psql "$SUPABASE_DB_URL" -f supabase/migrations/20260101000100_identity_and_coverage.sql
   # ... through 20260101001800_edge_support.sql
   ```

3. **Storage Setup**:
   Migration `20260101001600_storage.sql` automatically configures storage buckets and RLS policies for:
   - `product-images`
   - `invoices`
   - `delivery-proofs`
   - `return-evidence`

4. **Deploy Edge Functions**:
   ```bash
   npx supabase functions deploy request-otp --project-ref <PROJECT_REF>
   npx supabase functions deploy bootstrap-owner --project-ref <PROJECT_REF>
   npx supabase functions deploy generate-document --project-ref <PROJECT_REF>
   npx supabase functions deploy push-dispatch --project-ref <PROJECT_REF>
   npx supabase functions deploy assignment-expiry-worker --project-ref <PROJECT_REF>
   npx supabase functions deploy health --project-ref <PROJECT_REF>
   ```

5. **Bootstrap the Store Owner**:
   Invoke `bootstrap-owner` with your service role secret:
   ```bash
   curl -X POST "https://<PROJECT_REF>.supabase.co/functions/v1/bootstrap-owner" \
     -H "Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>" \
     -H "Content-Type: application/json" \
     -d '{"phone": "+919876543210", "full_name": "Store Owner"}'
   ```

---

## 2. Next.js Website Deployment

To deploy the storefront on Vercel, Netlify, or custom Node server:

1. Environment variables (`.env.production`):
   ```env
   NEXT_PUBLIC_SUPABASE_URL=https://<PROJECT_REF>.supabase.co
   NEXT_PUBLIC_SUPABASE_ANON_KEY=<ANON_KEY>
   ```

2. Build and verify:
   ```bash
   npm run build:web
   npm start -w @indibizz/website
   ```

---

## 3. Flutter Application Builds (APK, EXE & Web)

Ensure Flutter SDK is on your PATH (`tools/flutter/bin` or system `flutter`).

### Android APK Build
```bash
# Customer App APK
cd apps/customer_app
flutter pub get
flutter build apk --release

# Seller App APK
cd apps/seller_app
flutter pub get
flutter build apk --release

# Delivery Fleet App APK
cd apps/delivery_app
flutter pub get
flutter build apk --release
```
The output APKs will be located at:
`<app>/build/app/outputs/flutter-apk/app-release.apk`

### Windows EXE Build
Ensure Visual Studio "Desktop development with C++" workload is installed on Windows.
```bash
# Seller App Windows Executable
cd apps/seller_app
flutter pub get
flutter build windows --release

# Output executable located at:
# apps/seller_app/build/windows/x64/runner/Release/indibizz_seller.exe
```

### Web Builds
```bash
cd apps/seller_app
flutter build web --release
```
