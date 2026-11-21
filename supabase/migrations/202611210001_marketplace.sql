-- MAISON marketplace core schema. Apply with `supabase db push` after linking a project.
create extension if not exists pgcrypto;
create type public.app_role as enum ('customer','vendor','admin');
create type public.vendor_status as enum ('pending','approved','rejected','suspended','documents_requested');
create type public.product_status as enum ('draft','pending','approved','rejected','archived');
create type public.order_status as enum ('pending','confirmed','processing','shipped','delivered','cancelled','returned');
create type public.payment_status as enum ('pending','authorized','paid','failed','refunded');

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text, phone text, avatar_url text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.roles (user_id uuid not null references auth.users(id) on delete cascade, role public.app_role not null, primary key(user_id,role));
create table public.vendors (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null unique references auth.users(id) on delete cascade,
 owner_name text not null, business_name text not null, email text not null, phone text not null, business_address jsonb not null default '{}',
 gst_number text, pan_number text, business_type text, logo_url text,
 status public.vendor_status not null default 'pending', commission_percent numeric(5,2) not null default 15 check(commission_percent between 0 and 100),
 rejection_note text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.vendor_financials (vendor_id uuid primary key references public.vendors(id) on delete cascade, bank_account_encrypted text not null, updated_at timestamptz not null default now());
create table public.vendor_documents (
 id uuid primary key default gen_random_uuid(), vendor_id uuid not null references public.vendors(id) on delete cascade,
 document_type text not null, storage_path text not null, status text not null default 'pending' check(status in ('pending','approved','rejected','requested')),
 reviewer_note text, created_at timestamptz not null default now()
);
create table public.categories (id uuid primary key default gen_random_uuid(), name text not null, slug text unique not null, parent_id uuid references public.categories(id), image_url text, is_active boolean not null default true, sort_order int not null default 0);
create table public.brands (id uuid primary key default gen_random_uuid(), name text unique not null, slug text unique not null, logo_url text, is_active boolean not null default true);
create table public.products (
 id uuid primary key default gen_random_uuid(), vendor_id uuid not null references public.vendors(id), category_id uuid references public.categories(id), brand_id uuid references public.brands(id),
 name text not null, slug text unique not null, description text, material text, care_instructions text, price numeric(12,2) not null check(price>=0), compare_at_price numeric(12,2), status public.product_status not null default 'pending', average_rating numeric(3,2) not null default 0, review_count int not null default 0, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.product_images (id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id) on delete cascade, image_url text not null, alt_text text, sort_order int not null default 0, is_primary boolean not null default false);
create table public.product_variants (id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id) on delete cascade, sku text unique not null, size text, color text, color_hex text, price numeric(12,2), is_active boolean not null default true);
create table public.inventory (variant_id uuid primary key references public.product_variants(id) on delete cascade, quantity int not null default 0 check(quantity>=0), reserved int not null default 0 check(reserved>=0), updated_at timestamptz not null default now());
create table public.carts (id uuid primary key default gen_random_uuid(), user_id uuid not null unique references auth.users(id) on delete cascade, updated_at timestamptz not null default now());
create table public.cart_items (id uuid primary key default gen_random_uuid(), cart_id uuid not null references public.carts(id) on delete cascade, variant_id uuid not null references public.product_variants(id), quantity int not null check(quantity>0), unique(cart_id,variant_id));
create table public.wishlists (user_id uuid not null references auth.users(id) on delete cascade, product_id uuid not null references public.products(id) on delete cascade, created_at timestamptz not null default now(), primary key(user_id,product_id));
create table public.addresses (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, recipient_name text not null, phone text not null, line1 text not null, line2 text, city text not null, state text not null, postal_code text not null, country text not null default 'India', is_default boolean not null default false);
create table public.orders (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id), address_snapshot jsonb not null, status public.order_status not null default 'pending', subtotal numeric(12,2) not null, discount numeric(12,2) not null default 0, shipping numeric(12,2) not null default 0, total numeric(12,2) not null, coupon_id uuid, created_at timestamptz not null default now());
create table public.order_items (id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade, product_id uuid not null references public.products(id), variant_id uuid references public.product_variants(id), vendor_id uuid not null references public.vendors(id), product_name text not null, sku text, size text, color text, quantity int not null check(quantity>0), unit_price numeric(12,2) not null, commission_amount numeric(12,2) not null default 0, status public.order_status not null default 'pending', tracking_number text, shipping_carrier text);
create table public.payments (id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id), user_id uuid not null references auth.users(id), provider text not null, provider_payment_id text, amount numeric(12,2) not null, status public.payment_status not null default 'pending', payment_method text, created_at timestamptz not null default now());
create table public.coupons (id uuid primary key default gen_random_uuid(), code text unique not null, discount_type text not null check(discount_type in ('percent','fixed')), discount_value numeric(12,2) not null, min_order numeric(12,2) not null default 0, max_discount numeric(12,2), usage_limit int, used_count int not null default 0, starts_at timestamptz, ends_at timestamptz, is_active boolean not null default true);
alter table public.orders add constraint orders_coupon_fk foreign key(coupon_id) references public.coupons(id);
create table public.reviews (id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id), user_id uuid not null references auth.users(id), order_item_id uuid references public.order_items(id), rating int not null check(rating between 1 and 5), title text, body text, is_approved boolean not null default false, created_at timestamptz not null default now(), unique(user_id,product_id));
create table public.returns (id uuid primary key default gen_random_uuid(), order_item_id uuid not null references public.order_items(id), user_id uuid not null references auth.users(id), reason text not null, status text not null default 'requested', created_at timestamptz not null default now());
create table public.refunds (id uuid primary key default gen_random_uuid(), payment_id uuid not null references public.payments(id), order_id uuid not null references public.orders(id), amount numeric(12,2) not null, provider_ref text, status text not null default 'pending', created_at timestamptz not null default now());
create table public.vendor_commissions (id uuid primary key default gen_random_uuid(), vendor_id uuid not null references public.vendors(id), order_item_id uuid not null references public.order_items(id), rate numeric(5,2) not null, gross_amount numeric(12,2) not null, commission_amount numeric(12,2) not null, created_at timestamptz not null default now());
create table public.vendor_payouts (id uuid primary key default gen_random_uuid(), vendor_id uuid not null references public.vendors(id), amount numeric(12,2) not null, status text not null default 'pending', reference text, created_at timestamptz not null default now(), paid_at timestamptz);
create table public.notifications (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, title text not null, body text, read_at timestamptz, created_at timestamptz not null default now());
create table public.banners (id uuid primary key default gen_random_uuid(), title text not null, subtitle text, image_url text not null, href text, is_active boolean not null default false, starts_at timestamptz, ends_at timestamptz, sort_order int not null default 0);

create or replace function public.has_role(_role public.app_role) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.roles where user_id=auth.uid() and role=_role); $$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select public.has_role('admin'); $$;
create or replace function public.owns_vendor(_vendor uuid) returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.vendors where id=_vendor and owner_id=auth.uid() and status='approved'); $$;
create or replace function public.on_auth_user_created() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.profiles(id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name','')); insert into public.roles(user_id,role) values(new.id,'customer'); return new; end $$;
create trigger auth_user_profile after insert on auth.users for each row execute procedure public.on_auth_user_created();

-- Public catalog reads only approved, active items. All private mutations are role scoped.
do $$ declare t text; begin foreach t in array array['profiles','roles','vendors','vendor_financials','vendor_documents','categories','brands','products','product_images','product_variants','inventory','carts','cart_items','wishlists','addresses','orders','order_items','payments','coupons','reviews','returns','refunds','vendor_commissions','vendor_payouts','notifications','banners'] loop execute format('alter table public.%I enable row level security',t); end loop; end $$;
create policy "profile owner or admin read" on public.profiles for select using(id=auth.uid() or is_admin());
create policy "profile owner update" on public.profiles for update using(id=auth.uid() or is_admin()) with check(id=auth.uid() or is_admin());
create policy "role owner read" on public.roles for select using(user_id=auth.uid() or is_admin()); create policy "admin role manage" on public.roles for all using(is_admin()) with check(is_admin());
drop policy if exists "vendor public approved read" on public.vendors;
create policy "vendor private owner admin read" on public.vendors for select using(owner_id=auth.uid() or is_admin());
create policy "vendor apply" on public.vendors for insert with check(owner_id=auth.uid() and status='pending'); create policy "vendor owner update" on public.vendors for update using(owner_id=auth.uid() and status in ('pending','documents_requested') or is_admin()) with check(owner_id=auth.uid() and status in ('pending','documents_requested') or is_admin());
create policy "vendor financials private read" on public.vendor_financials for select using(is_admin() or exists(select 1 from vendors v where v.id=vendor_id and v.owner_id=auth.uid()));
create policy "vendor financials admin manage" on public.vendor_financials for all using(is_admin()) with check(is_admin());
create policy "documents owner admin read" on public.vendor_documents for select using(exists(select 1 from vendors v where v.id=vendor_id and (v.owner_id=auth.uid() or is_admin())));
create policy "documents owner upload" on public.vendor_documents for insert with check(status='pending' and exists(select 1 from vendors v where v.id=vendor_id and v.owner_id=auth.uid()));
create policy "documents admin review" on public.vendor_documents for update using(is_admin()) with check(is_admin());
create policy "categories visible" on public.categories for select using(is_active or is_admin()); create policy "categories admin" on public.categories for all using(is_admin()) with check(is_admin());
create policy "brands visible" on public.brands for select using(is_active or is_admin()); create policy "brands admin" on public.brands for all using(is_admin()) with check(is_admin());
create policy "approved products visible" on public.products for select using(status='approved' or is_admin() or exists(select 1 from vendors v where v.id=vendor_id and v.owner_id=auth.uid()));
create policy "vendors manage own products" on public.products for insert with check(exists(select 1 from vendors v where v.id=vendor_id and v.owner_id=auth.uid() and v.status='approved'));
drop policy "vendors update own products" on public.products;
drop policy "vendors delete own products" on public.products;
create policy "admin product management" on public.products for all using(is_admin()) with check(is_admin());
create policy "vendors update own products" on public.products for update using(owns_vendor(vendor_id)) with check(owns_vendor(vendor_id) and status in ('draft','pending','rejected'));
create policy "vendors delete own products" on public.products for delete using(owns_vendor(vendor_id) and status in ('draft','rejected'));
create policy "images follow product visibility" on public.product_images for select using(exists(select 1 from products p where p.id=product_id and (p.status='approved' or is_admin() or exists(select 1 from vendors v where v.id=p.vendor_id and v.owner_id=auth.uid()))));
create policy "product image vendors manage" on public.product_images for all using(exists(select 1 from products p where p.id=product_id and (owns_vendor(p.vendor_id) or is_admin()))) with check(exists(select 1 from products p where p.id=product_id and (owns_vendor(p.vendor_id) or is_admin())));
create policy "variants visible with product" on public.product_variants for select using(exists(select 1 from products p where p.id=product_id and (p.status='approved' or is_admin() or exists(select 1 from vendors v where v.id=p.vendor_id and v.owner_id=auth.uid()))));
create policy "variant owner management" on public.product_variants for all using(exists(select 1 from products p where p.id=product_id and (owns_vendor(p.vendor_id) or is_admin()))) with check(exists(select 1 from products p where p.id=product_id and (owns_vendor(p.vendor_id) or is_admin())));
create policy "inventory public read" on public.inventory for select using(exists(select 1 from product_variants pv join products p on p.id=pv.product_id where pv.id=variant_id and p.status='approved'));
create policy "inventory vendor manage" on public.inventory for all using(exists(select 1 from product_variants pv join products p on p.id=pv.product_id where pv.id=variant_id and (owns_vendor(p.vendor_id) or is_admin()))) with check(exists(select 1 from product_variants pv join products p on p.id=pv.product_id where pv.id=variant_id and (owns_vendor(p.vendor_id) or is_admin())));
create policy "cart owner" on public.carts for all using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy "cart item owner" on public.cart_items for all using(exists(select 1 from carts c where c.id=cart_id and c.user_id=auth.uid())) with check(exists(select 1 from carts c where c.id=cart_id and c.user_id=auth.uid()));
create policy "wishlist owner" on public.wishlists for all using(user_id=auth.uid()) with check(user_id=auth.uid()); create policy "address owner" on public.addresses for all using(user_id=auth.uid() or is_admin()) with check(user_id=auth.uid() or is_admin());
create policy "order customer/vendor/admin read" on public.orders for select using(user_id=auth.uid() or is_admin() or exists(select 1 from order_items oi join vendors v on v.id=oi.vendor_id where oi.order_id=id and v.owner_id=auth.uid()));
create policy "order admin update" on public.orders for update using(is_admin()) with check(is_admin());
create policy "order item scoped read" on public.order_items for select using(exists(select 1 from orders o where o.id=order_id and o.user_id=auth.uid()) or exists(select 1 from vendors v where v.id=vendor_id and v.owner_id=auth.uid()) or is_admin());
create policy "order item system write" on public.order_items for all using(is_admin()) with check(is_admin());
create policy "payments owner read" on public.payments for select using(user_id=auth.uid() or is_admin()); create policy "payments system write" on public.payments for all using(is_admin()) with check(is_admin());
create policy "active coupons visible" on public.coupons for select using(is_active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()) or is_admin()); create policy "coupon admin" on public.coupons for all using(is_admin()) with check(is_admin());
create policy "approved reviews public" on public.reviews for select using(is_approved or user_id=auth.uid() or is_admin()); create policy "review owner create" on public.reviews for insert with check(user_id=auth.uid()); create policy "review moderation" on public.reviews for update using(is_admin()) with check(is_admin());
create policy "return owner/vendor/admin" on public.returns for select using(user_id=auth.uid() or is_admin() or exists(select 1 from order_items oi join vendors v on v.id=oi.vendor_id where oi.id=order_item_id and v.owner_id=auth.uid())); create policy "return customer create" on public.returns for insert with check(user_id=auth.uid()); create policy "return admin update" on public.returns for update using(is_admin()) with check(is_admin());
create policy "refund admin/customer read" on public.refunds for select using(is_admin() or exists(select 1 from orders o where o.id=order_id and o.user_id=auth.uid())); create policy "refund admin write" on public.refunds for all using(is_admin()) with check(is_admin());
create policy "commission vendor read" on public.vendor_commissions for select using(owns_vendor(vendor_id) or is_admin()); create policy "commission admin write" on public.vendor_commissions for all using(is_admin()) with check(is_admin());
create policy "payout vendor/admin read" on public.vendor_payouts for select using(owns_vendor(vendor_id) or is_admin()); create policy "payout admin write" on public.vendor_payouts for all using(is_admin()) with check(is_admin());
create policy "notification owner" on public.notifications for all using(user_id=auth.uid() or is_admin()) with check(user_id=auth.uid() or is_admin());
create policy "active banners visible" on public.banners for select using(is_active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()) or is_admin()); create policy "banner admin" on public.banners for all using(is_admin()) with check(is_admin());
create index products_catalog_idx on public.products(status,category_id,brand_id,price); create index orders_customer_idx on public.orders(user_id,created_at desc); create index order_items_vendor_idx on public.order_items(vendor_id,order_id); create index notifications_user_idx on public.notifications(user_id,created_at desc);
create table public.newsletter_subscribers (id uuid primary key default gen_random_uuid(), email text not null unique, created_at timestamptz not null default now());
alter table public.newsletter_subscribers enable row level security;
create policy "newsletter public subscribe" on public.newsletter_subscribers for insert with check (length(email) between 5 and 320 and position('@' in email)>1);
create policy "newsletter admin read" on public.newsletter_subscribers for select using(is_admin());

-- Trusted checkout only: called by the service-role Edge Function after resolving the authenticated user.
create or replace function public.create_marketplace_order(p_user_id uuid,p_items jsonb,p_address jsonb,p_payment_method text,p_coupon_code text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare entry jsonb; v record; c coupons%rowtype; line_total numeric(12,2); sub numeric(12,2):=0; disc numeric(12,2):=0; ship numeric(12,2):=0; new_order uuid; count_items int:=0;
begin
 if p_payment_method not in ('cod','razorpay') then raise exception 'Unsupported payment method'; end if;
 if p_user_id is null or coalesce(p_address->>'recipient_name','')='' or coalesce(p_address->>'phone','')='' or coalesce(p_address->>'line1','')='' or coalesce(p_address->>'postal_code','')='' then raise exception 'A complete delivery address is required'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'The bag is empty'; end if;
 if (select count(distinct value->>'variant_id') from jsonb_array_elements(p_items))<>jsonb_array_length(p_items) then raise exception 'Remove duplicate bag items before checkout'; end if;
 -- Lock and validate every variant before writing an order. Client prices are never used.
 for entry in select value from jsonb_array_elements(p_items) loop
   if coalesce((entry->>'quantity')::int,0)<1 or (entry->>'quantity')::int>20 then raise exception 'Invalid quantity'; end if;
   select pv.id,pv.product_id,pv.sku,coalesce(pv.price,p.price) unit_price,pv.size,pv.color,p.vendor_id,p.name product_name,v.status vendor_status,coalesce(i.quantity,0)-coalesce(i.reserved,0) available
   into v from product_variants pv join products p on p.id=pv.product_id join vendors v on v.id=p.vendor_id join inventory i on i.variant_id=pv.id where pv.id=(entry->>'variant_id')::uuid and pv.is_active and p.status='approved' and v.status='approved' for update of pv,i;
   if not found then raise exception 'A product is unavailable'; end if;
   if v.available < (entry->>'quantity')::int then raise exception 'Insufficient stock for %',v.product_name; end if;
   sub:=sub+(v.unit_price*(entry->>'quantity')::int); count_items:=count_items+1;
 end loop;
 if p_coupon_code is not null and btrim(p_coupon_code)<>'' then
   select * into c from coupons where upper(code)=upper(btrim(p_coupon_code)) and is_active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()) for update;
   if not found or sub<c.min_order or (c.usage_limit is not null and c.used_count>=c.usage_limit) then raise exception 'This coupon is invalid or unavailable'; end if;
   disc:=case when c.discount_type='percent' then sub*c.discount_value/100 else c.discount_value end;
   if c.max_discount is not null then disc:=least(disc,c.max_discount); end if;
   disc:=least(sub,greatest(0,disc)); update coupons set used_count=used_count+1 where id=c.id;
 end if;
 ship:=case when sub>=2999 then 0 else 99 end;
 insert into orders(user_id,address_snapshot,status,subtotal,discount,shipping,total,coupon_id)
 values(p_user_id,p_address,case when p_payment_method='cod' then 'confirmed'::order_status else 'pending'::order_status,sub,disc,ship,sub-disc+ship,c.id)
 returning id into new_order;
 for entry in select value from jsonb_array_elements(p_items) loop
   select pv.id,pv.product_id,pv.sku,coalesce(pv.price,p.price) unit_price,pv.size,pv.color,p.vendor_id,p.name product_name,v.commission_percent
   into v from product_variants pv join products p on p.id=pv.product_id join vendors v on v.id=p.vendor_id where pv.id=(entry->>'variant_id')::uuid;
   line_total:=v.unit_price*(entry->>'quantity')::int;
   insert into order_items(order_id,product_id,variant_id,vendor_id,product_name,sku,size,color,quantity,unit_price,commission_amount,status)
   values(new_order,v.product_id,v.id,v.vendor_id,v.product_name,v.sku,v.size,v.color,(entry->>'quantity')::int,v.unit_price,line_total*v.commission_percent/100,case when p_payment_method='cod' then 'confirmed'::order_status else 'pending'::order_status end);
   if p_payment_method='cod' then update inventory set quantity=quantity-(entry->>'quantity')::int,updated_at=now() where variant_id=v.id; else update inventory set reserved=reserved+(entry->>'quantity')::int,updated_at=now() where variant_id=v.id; end if;
 end loop;
 return jsonb_build_object('id',new_order,'total',sub-disc+ship,'discount',disc,'total_paise',((sub-disc+ship)*100)::int);
end $$;
revoke all on function public.create_marketplace_order(uuid,jsonb,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.create_marketplace_order(uuid,jsonb,jsonb,text,text) to service_role;
-- Product owners may submit for review but cannot self-approve.
drop policy "vendors manage own products" on public.products;
create policy "vendors submit products for review" on public.products for insert with check(status in ('draft','pending') and exists(select 1 from vendors v where v.id=vendor_id and v.owner_id=auth.uid() and v.status='approved'));
-- Storage: catalog media can be read publicly; writes and private documents stay scoped to authenticated owners.
insert into storage.buckets(id,name,public) values('product-media','product-media',true),('vendor-documents','vendor-documents',false) on conflict(id) do nothing;
create policy "public read product media" on storage.objects for select using(bucket_id='product-media');
create policy "vendor media upload own folder" on storage.objects for insert to authenticated with check(bucket_id='product-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "vendor media update own folder" on storage.objects for update to authenticated using(bucket_id='product-media' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='product-media' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "private vendor docs owner admin read" on storage.objects for select to authenticated using(bucket_id='vendor-documents' and ((storage.foldername(name))[1]=auth.uid()::text or is_admin()));
create policy "vendor docs upload own folder" on storage.objects for insert to authenticated with check(bucket_id='vendor-documents' and (storage.foldername(name))[1]=auth.uid()::text);

create or replace function public.finalize_marketplace_order(p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare oi record; locked_order uuid;
begin
 select id into locked_order from orders where id=p_order_id and status='pending' for update; if not found then return; end if;
 for oi in select variant_id,quantity from order_items where order_id=p_order_id and variant_id is not null for update loop
   update inventory set quantity=quantity-oi.quantity,reserved=reserved-oi.quantity,updated_at=now() where variant_id=oi.variant_id and reserved>=oi.quantity and quantity>=oi.quantity;
   if not found then raise exception 'Inventory reservation could not be finalized'; end if;
 end loop;
 update orders set status='confirmed' where id=p_order_id and status='pending';
 update order_items set status='confirmed' where order_id=p_order_id and status='pending';
end $$;
revoke all on function public.finalize_marketplace_order(uuid) from public,anon,authenticated;
grant execute on function public.finalize_marketplace_order(uuid) to service_role;
create or replace function public.release_marketplace_order(p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare oi record; coupon uuid; locked_order uuid;
begin
 select id,coupon_id into locked_order,coupon from orders where id=p_order_id and status='pending' for update; if not found then return; end if;
 for oi in select variant_id,quantity from order_items where order_id=p_order_id and variant_id is not null for update loop
   update inventory set reserved=greatest(0,reserved-oi.quantity),updated_at=now() where variant_id=oi.variant_id;
 end loop;
 if coupon is not null then update coupons set used_count=greatest(0,used_count-1) where id=coupon; end if;
 delete from orders where id=p_order_id and status='pending';
end $$;
revoke all on function public.release_marketplace_order(uuid) from public,anon,authenticated;
grant execute on function public.release_marketplace_order(uuid) to service_role;

create or replace function public.cancel_customer_order(p_order_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare o orders%rowtype; oi record;
begin
 select * into o from orders where id=p_order_id and user_id=p_user_id for update;
 if not found then raise exception 'Order not found'; end if;
 if o.status not in ('pending','confirmed') then raise exception 'This order can no longer be cancelled'; end if;
 if exists(select 1 from payments where order_id=p_order_id and status='paid') then raise exception 'Paid order requires support-assisted refund'; end if;
 for oi in select variant_id,quantity from order_items where order_id=p_order_id and variant_id is not null for update loop
   if o.status='pending' then update inventory set reserved=greatest(0,reserved-oi.quantity),updated_at=now() where variant_id=oi.variant_id;
   else update inventory set quantity=quantity+oi.quantity,updated_at=now() where variant_id=oi.variant_id; end if;
 end loop;
 update orders set status='cancelled' where id=p_order_id;
 update order_items set status='cancelled' where order_id=p_order_id;
end $$;
revoke all on function public.cancel_customer_order(uuid,uuid) from public,anon,authenticated;
grant execute on function public.cancel_customer_order(uuid,uuid) to service_role;

create unique index returns_one_active_request on public.returns(order_item_id) where status in ('requested','approved','pickup_scheduled');

insert into public.coupons(code,discount_type,discount_value,min_order,max_discount,is_active) values('ELAN15','percent',15,0,1000,true) on conflict(code) do nothing;
