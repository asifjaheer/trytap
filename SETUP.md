# TryTap admin: setup & deployment

## What your project was
A **single static `index.html`** (712 lines, ~49 KB): no backend, no build step, no database. Prices, FAQs and contact
details were hardcoded, and the enquiry form is UI-only. (I can only see the file you uploaded, so I can't tell where,
or whether, it is hosted.) Because it is static, edits made in a browser can't be saved for other visitors. localStorage
only lives in one browser and anyone could tamper with it, so real cross-device editing needs a backend + authentication.

## Architecture (all free-tier friendly)
```
Browser (public site)  --anon key, read-only-->  Supabase Postgres  (RLS: only PUBLISHED rows are readable)
Browser (/admin)       --signs in via Supabase Auth--> JWT --> RLS checks is_admin() on EVERY write
```
* No password exists in any file. Login is handled by Supabase Auth (hashed passwords, rate limiting).
* Authorisation is enforced **by the database** (Row Level Security), not by the admin page. Even someone who edits the
  admin JavaScript cannot write data without an admin account.
* The only key in the project is the public **anon/publishable** key. Never use the `service_role`/secret key in these files.

## Files
| File | Action |
|---|---|
| `index.html` | **Replace** yours (your design is untouched; hooks + loader added) |
| `config.js` | **New**: put your Supabase URL + anon key here |
| `admin/index.html` | **New**: the dashboard, served at `/admin` |
| `supabase/schema.sql` | **New**: run once in Supabase (not deployed to your site; you can leave it out of the upload) |
| `_headers` | **New, optional**: security headers on Netlify / Cloudflare Pages |

## Step 1: Create the Supabase project
1. Sign up at supabase.com, then **New project** (choose a region near your users, e.g. Mumbai `ap-south-1`).
2. **SQL Editor > New query**, paste all of `supabase/schema.sql`, **Run**. It creates tables, RLS policies, the
   `product-images` storage bucket, and seeds your current 3 products, 5 FAQs and contact text.
   The seeded prices are **INR placeholders (₹999 / ₹1,999 / ₹4,999)**; edit them in the admin.

## Step 2: Create your admin account
1. **Authentication > Users > Add user > Create new user**: your email + a strong, unique password; tick *Auto Confirm*.
2. **Authentication > Sign In / Providers**: turn **off** "Allow new users to sign up" (nobody else needs an account).
3. **SQL Editor**: run (with your email):
   ```sql
   insert into public.admin_users (user_id) select id from auth.users where email = 'you@example.com';
   ```
   Only accounts listed in `admin_users` can write anything. Everyone else, including other logged-in users, is read-only.

## Step 3: Connect the site
1. **Project Settings > API** (or *API Keys*): copy the **Project URL** and the **anon / publishable** key.
2. Edit `config.js` with those two values. Do **not** copy the `service_role` / secret key anywhere.

## Step 4: Deploy (any static host; no build command)
* **Netlify**: drag the project folder onto app.netlify.com/drop, or connect a Git repo (publish dir = `.`, no build command).
* **Cloudflare Pages**: create a project, upload the folder / connect Git, framework preset "None".
* **Vercel**: import the repo, framework "Other", no build command. (`_headers` is ignored; add the same headers in `vercel.json` if you want them.)
* **GitHub Pages**: works too (`/admin/` URL). `_headers` is ignored.

Then open `https://YOUR-SITE/admin`, sign in, and edit.
Local testing: `npx serve .` or `python3 -m http.server`, then open `/admin/`.

## Step 5: Verify it for real (do this before trusting it)
I tested the UI logic with a mocked Supabase client; I could **not** reach a live Supabase project from my sandbox, so
please run these checks against yours:
1. `/admin` shows the sign-in form; a wrong password is rejected.
2. Edit a price (e.g. TryTap Pro to ₹2,199), Save, then refresh the public site **on your phone**. The new price must show.
3. Unpublish a product, then refresh the public site; it must disappear. Publish it again.
4. **Security check**: open your public site in a private window and run in DevTools console:
   `fetch(TRYTAP_CONFIG.SUPABASE_URL+'/rest/v1/products',{method:'POST',headers:{apikey:TRYTAP_CONFIG.SUPABASE_ANON_KEY,'Content-Type':'application/json'},body:'{"name":"hack","slug":"hack","price_minor":1}'}).then(r=>r.status)`
   It must return **401/403** (denied). Also confirm unpublished products are not returned by `/rest/v1/products` without logging in.
5. In Supabase, **Authentication > Users**, confirm only you exist.

If a save fails, the admin shows the real error and does **not** claim success (it checks that the database actually changed a row).

## How pricing works
* Amounts are stored as **integer minor units** (paise/cents) plus a **currency code** per product: `199900 + INR` = ₹1,999.
  No floating point anywhere. You type `1999` or `1,999.50` in the admin; it converts exactly.
* Display uses the browser's `Intl.NumberFormat` with the **locale** from *Settings* (`en-IN` gives ₹1,99,900-style grouping).
  Whole amounts show without decimals (₹1,999), fractional ones show decimals (₹1,999.50).
* *Settings > Default currency* only sets the default for **new** products; it never rewrites existing prices.
* Future international markets: keep this schema for the "base" price and later add a `product_prices(product_id, currency, amount_minor)` table. The formatting code already handles any ISO currency.

## What changed in `index.html` (so you can review the diff)
* `config.js` + a tiny inline script (adds a `pending` class so old text doesn't flash before data loads; auto-clears after 2.5 s).
* `data-c` / `data-contact` attributes on hero text, CTAs, tagline, footer; `id="product-grid"` on the products wrapper.
* A loader script at the end that fetches published products, FAQs and site content, then renders with `textContent` (XSS-safe).
* Two small hooks in your existing script: `window.TryTapReveal` (so new cards still animate in) and the FAQ accordion
  wrapped in a re-callable `initFaq()` (behaviour unchanged).
* A small CSS block for compare-at prices, categories, stock labels and product images.
* **Fallback:** if `config.js` still has placeholders, or Supabase is unreachable, the original static content stays on the page.
* Category now shows as a small label above each product name (new field). Delete the `.pcat` line in the loader if you don't want it.

## Known limits / next steps
* **The enquiry form is still demo-only** (as in your original): it sends nothing. Connect Formspree/Web3Forms, or add an `enquiries` table + insert-only policy.
* Footer line "Contact details and links above are placeholders" and the social-link `#` placeholders are still static text; edit them in `index.html`.
* No checkout; the "go" arrow just takes visitors to the enquiry form with the product pre-selected.
* Enable **MFA (TOTP)** in Supabase Auth for the admin account and use a unique password; the admin page itself has no MFA prompt UI yet.
* The Supabase session token is kept in the browser's localStorage by `supabase-js` (standard). Use a trusted device and sign out on shared computers. `admin/index.html` pins `supabase-js@2.45.4` from jsDelivr; for stricter supply-chain control, self-host that file.
* Deleting images: uploaded files are removed from storage when their product is deleted or its image replaced (unless another product still uses it). Unsaved uploads can leave an orphan file; clean up in Supabase Storage if needed.
