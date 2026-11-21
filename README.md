# ÉLAN Fashion Marketplace

Premium fashion marketplace frontend built with React, TypeScript, Tailwind CSS, Lucide, and Supabase.

## Run locally

1. Install dependencies with `npm install`.
2. Copy `.env.example` to `.env.local` and set the Supabase project URL and anon key.
3. Apply the database migration in `supabase/migrations/202611210001_marketplace.sql` using the Supabase CLI (`supabase db push`) or SQL editor.
4. Start with `npm run dev`.

Without Supabase credentials the storefront runs in preview mode with a curated sample catalog. Backend account, catalog, vendor, and checkout operations require a configured Supabase project and deployed Edge Functions. Never expose Razorpay secret credentials in the browser.

## Supabase setup notes

- Enable email/password auth and configure email verification in Supabase Auth.
- Create a public `product-media` Storage bucket and use Storage policies that restrict writes to approved product owners; keep vendor identity/bank documents in a private bucket.
- Bootstrap the first administrator by inserting the user's ID into `public.roles` with role `admin` via a trusted SQL session.
- Razorpay order creation and signature verification run in Edge Functions; configure the server secrets before choosing Razorpay checkout.
- Vendor payout account data must be encrypted in a trusted backend process before persistence; the client has no access to it under RLS.

## Deploying marketplace functions

Run `supabase functions deploy vendor-application`, `supabase functions deploy admin-vendor-review`, `supabase functions deploy admin-product-review`, `supabase functions deploy admin-dashboard`, `supabase functions deploy marketplace-checkout`, and `supabase functions deploy verify-razorpay-payment`, `supabase functions deploy customer-order-action`, and `supabase functions deploy vendor-order-action` after linking the project. Set secrets with `supabase secrets set RAZORPAY_KEY_ID=... RAZORPAY_KEY_SECRET=... VENDOR_DATA_KEY=... APP_ORIGIN=https://your-store.example`. `VENDOR_DATA_KEY` must be a base64 encoded, 32-byte random key. Keep all of these values in the Edge Function environment. Configure Google OAuth in Supabase Auth if that sign-in option is required.

Implemented in this iteration: vendor onboarding with encrypted payout details and private document uploads, application review/status notifications, vendor product submissions and shipping updates, admin vendor/product review and metrics, customer profile/order views, cancellation/return requests, password recovery, Google OAuth, product facets, coupons, COD and Razorpay checkout with server price/stock checks and signature verification.

Still needed for a full production marketplace: complete returns/refunds and payout operations, customer address book, bulk product import, complete vendor analytics/commission screens, category/brand/coupon/banner/settings and customer-management admin CRUD, review moderation and Q&A, loyalty/gift/referral/compare/recommendation flows, support/FAQ and WhatsApp, full product videos/gallery editing, and expired payment reservation cleanup. The Supabase migration and Edge Functions have not been applied/deployed to a live project here. Set credentials, configure Auth providers, and deploy functions before exercising backend paths.
