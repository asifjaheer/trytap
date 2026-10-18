-- =====================================================================
-- TryTap admin backend: schema, Row Level Security and seed data
-- Run once in: Supabase Dashboard > SQL Editor > New query > Run
-- Safe to re-run (uses IF NOT EXISTS / ON CONFLICT / DROP POLICY IF EXISTS).
-- =====================================================================

-- 1. Who is an admin? Only rows in this table. Accounts are NOT admins just
--    because they can sign in. Rows can only be added from the SQL editor.
create table if not exists public.admin_users (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$ select exists (select 1 from public.admin_users where user_id = auth.uid()) $$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

drop policy if exists "admins can read own admin row" on public.admin_users;
create policy "admins can read own admin row" on public.admin_users
  for select to authenticated using (user_id = auth.uid());
-- (no insert/update/delete policies on purpose: nobody can grant themselves admin via the API)

-- 2. Shared updated_at trigger
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

-- 3. Products. Money is stored as INTEGER MINOR UNITS (paise for INR, cents for USD)
--    so there is never any floating point rounding. 199900 + 'INR' = Rs 1,999.00
create table if not exists public.products (
  id               uuid primary key default gen_random_uuid(),
  name             text not null check (char_length(name) between 2 and 80),
  slug             text not null unique
                   check (char_length(slug) <= 80 and slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  description      text not null default '' check (char_length(description) <= 600),
  price_minor      bigint not null check (price_minor >= 0 and price_minor <= 1000000000000),
  compare_at_minor bigint check (compare_at_minor is null or compare_at_minor > price_minor),
  currency         text not null default 'INR' check (currency ~ '^[A-Z]{3}$'),
  image_url        text check (image_url is null or image_url ~ '^https://'),
  category         text not null default '' check (char_length(category) <= 40),
  features         text[] not null default '{}' check (cardinality(features) <= 8),
  availability     text not null default 'in_stock'
                   check (availability in ('in_stock','out_of_stock','preorder','coming_soon')),
  is_featured      boolean not null default false,
  published        boolean not null default false,
  sort_order       integer not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
drop trigger if exists products_updated_at on public.products;
create trigger products_updated_at before update on public.products
  for each row execute function public.set_updated_at();

-- 4. Website copy: exactly one row (id = 1)
create table if not exists public.site_content (
  id                  integer primary key check (id = 1),
  hero_heading        text not null default 'Networking.'  check (char_length(hero_heading) <= 80),
  hero_heading_accent text not null default 'Reimagined.'  check (char_length(hero_heading_accent) <= 80),
  hero_subtext        text not null default '' check (char_length(hero_subtext) <= 300),
  hero_cta_primary    text not null default 'Get Your TryTap Card' check (char_length(hero_cta_primary) <= 40),
  hero_cta_secondary  text not null default 'See How It Works'     check (char_length(hero_cta_secondary) <= 40),
  nav_cta             text not null default 'Shop Now'             check (char_length(nav_cta) <= 30),
  tagline             text not null default 'Tap In. Stand Out.'   check (char_length(tagline) <= 80),
  products_lead       text not null default '' check (char_length(products_lead) <= 300),
  about_text          text not null default '' check (char_length(about_text) <= 300),
  contact_email       text not null default '' check (char_length(contact_email) <= 120),
  contact_phone       text not null default '' check (char_length(contact_phone) <= 40),
  contact_address     text not null default '' check (char_length(contact_address) <= 200),
  default_currency    text not null default 'INR'   check (default_currency ~ '^[A-Z]{3}$'),
  locale              text not null default 'en-IN' check (locale ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  updated_at          timestamptz not null default now()
);
drop trigger if exists site_content_updated_at on public.site_content;
create trigger site_content_updated_at before update on public.site_content
  for each row execute function public.set_updated_at();

-- 5. FAQs
create table if not exists public.faqs (
  id         uuid primary key default gen_random_uuid(),
  question   text not null check (char_length(question) between 3 and 200),
  answer     text not null check (char_length(answer) between 3 and 1500),
  published  boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists faqs_updated_at on public.faqs;
create trigger faqs_updated_at before update on public.faqs
  for each row execute function public.set_updated_at();

-- 6. Row Level Security: public may READ published/public data only; only admins write.
alter table public.products     enable row level security;
alter table public.site_content enable row level security;
alter table public.faqs         enable row level security;

grant select on public.products, public.faqs, public.site_content to anon;
grant select, insert, update, delete on public.products, public.faqs, public.site_content to authenticated;

-- products
drop policy if exists "public reads published products" on public.products;
create policy "public reads published products" on public.products
  for select to anon, authenticated using (published = true);
drop policy if exists "admins read all products" on public.products;
create policy "admins read all products" on public.products
  for select to authenticated using (public.is_admin());
drop policy if exists "admins insert products" on public.products;
create policy "admins insert products" on public.products
  for insert to authenticated with check (public.is_admin());
drop policy if exists "admins update products" on public.products;
create policy "admins update products" on public.products
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admins delete products" on public.products;
create policy "admins delete products" on public.products
  for delete to authenticated using (public.is_admin());

-- site_content
drop policy if exists "public reads site content" on public.site_content;
create policy "public reads site content" on public.site_content
  for select to anon, authenticated using (true);
drop policy if exists "admins insert site content" on public.site_content;
create policy "admins insert site content" on public.site_content
  for insert to authenticated with check (public.is_admin());
drop policy if exists "admins update site content" on public.site_content;
create policy "admins update site content" on public.site_content
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- faqs
drop policy if exists "public reads published faqs" on public.faqs;
create policy "public reads published faqs" on public.faqs
  for select to anon, authenticated using (published = true);
drop policy if exists "admins read all faqs" on public.faqs;
create policy "admins read all faqs" on public.faqs
  for select to authenticated using (public.is_admin());
drop policy if exists "admins insert faqs" on public.faqs;
create policy "admins insert faqs" on public.faqs
  for insert to authenticated with check (public.is_admin());
drop policy if exists "admins update faqs" on public.faqs;
create policy "admins update faqs" on public.faqs
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "admins delete faqs" on public.faqs;
create policy "admins delete faqs" on public.faqs
  for delete to authenticated using (public.is_admin());

-- 7. Product image storage (public read, admin-only write)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 2097152,
        array['image/jpeg','image/png','image/webp','image/avif'])
on conflict (id) do update
  set public = true, file_size_limit = 2097152,
      allowed_mime_types = array['image/jpeg','image/png','image/webp','image/avif'];

drop policy if exists "admins read product images" on storage.objects;
create policy "admins read product images" on storage.objects
  for select to authenticated using (bucket_id = 'product-images' and public.is_admin());
drop policy if exists "admins upload product images" on storage.objects;
create policy "admins upload product images" on storage.objects
  for insert to authenticated with check (bucket_id = 'product-images' and public.is_admin());
drop policy if exists "admins update product images" on storage.objects;
create policy "admins update product images" on storage.objects
  for update to authenticated using (bucket_id = 'product-images' and public.is_admin());
drop policy if exists "admins delete product images" on storage.objects;
create policy "admins delete product images" on storage.objects
  for delete to authenticated using (bucket_id = 'product-images' and public.is_admin());
-- Public image URLs work without a SELECT policy because the bucket is public.

-- 8. Seed data = your current website content (prices are INR PLACEHOLDERS: edit them in the admin)
insert into public.site_content (id, hero_subtext, products_lead, about_text, contact_email, contact_phone, contact_address)
values (1,
  'One tap is all it takes to share your world. Meet TryTap — the smarter way to connect.',
  'From individuals to growing teams, we have the perfect TryTap for you.',
  'Premium NFC digital business cards. Tap In. Stand Out.',
  'hello@example.com', '+91 00000 00000', 'Mumbai, India')
on conflict (id) do nothing;

insert into public.products (name, slug, description, price_minor, currency, category, features, is_featured, published, sort_order) values
 ('TryTap Essential','trytap-essential','A simple NFC business card for everyday networking.', 99900,'INR','Individual',
  array['One-tap profile sharing','Custom digital profile','QR code backup','Minimal premium design'], false, true, 1),
 ('TryTap Pro','trytap-pro','A premium NFC card for ambitious professionals.', 199900,'INR','Professional',
  array['Premium card finish','Custom branding','Digital contact sharing','Social media integration'], true, true, 2),
 ('TryTap Business','trytap-business','Smart networking solutions for growing teams.', 499900,'INR','Teams',
  array['Custom branded NFC cards','Team profile management','Consistent company branding','Scalable business solutions'], false, true, 3)
on conflict (slug) do nothing;

insert into public.faqs (question, answer, sort_order)
select q, a, n from (values
 ('What is an NFC digital business card?', $$It's a physical card with a small NFC chip inside. When tapped on a compatible smartphone, it opens your digital profile — contact details, links and socials — without any paper.$$, 1),
 ('Does the other person need an app?', $$No app is required for basic link sharing. Compatible smartphones open your profile link directly in the browser.$$, 2),
 ('What if someone''s phone doesn''t support NFC?', $$Every TryTap profile includes a QR code backup, so anyone can scan it with their camera to open your profile.$$, 3),
 ('Can I customise my profile and card?', $$Yes. You can personalise your digital profile, and Pro and Business options support custom branding.$$, 4),
 ('Can my whole team use TryTap?', $$TryTap Business is built for teams, with consistent company branding and team profile management. Use the enquiry form to tell us about your team.$$, 5)
) as v(q, a, n)
where not exists (select 1 from public.faqs);

-- 9. AFTER creating your admin user in Authentication > Users, run this (replace the email):
--    insert into public.admin_users (user_id) select id from auth.users where email = 'you@example.com';
