-- Allow approved vendors to edit their own storefront and product details without granting review authority.
alter table public.returns add column if not exists reviewer_note text;
alter table public.products add column if not exists rejection_note text;

delete from public.vendor_commissions a using public.vendor_commissions b where a.order_item_id=b.order_item_id and a.ctid>b.ctid;
create unique index if not exists vendor_commissions_order_item_key on public.vendor_commissions(order_item_id);
insert into public.vendor_commissions(vendor_id,order_item_id,rate,gross_amount,commission_amount,created_at)
select oi.vendor_id,oi.id,case when oi.unit_price*oi.quantity=0 then 0 else oi.commission_amount/(oi.unit_price*oi.quantity)*100 end,oi.unit_price*oi.quantity,oi.commission_amount,o.created_at
from public.order_items oi join public.orders o on o.id=oi.order_id
on conflict(order_item_id) do nothing;
create or replace function public.record_vendor_commission()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.vendor_commissions(vendor_id,order_item_id,rate,gross_amount,commission_amount)
 values(new.vendor_id,new.id,case when new.unit_price*new.quantity=0 then 0 else new.commission_amount/(new.unit_price*new.quantity)*100 end,new.unit_price*new.quantity,new.commission_amount)
 on conflict(order_item_id) do nothing;
 return new;
end $$;
create trigger record_order_item_commission after insert on public.order_items for each row execute function public.record_vendor_commission();

create table if not exists public.marketplace_settings (
 setting_key text primary key,
 value jsonb not null default '{}'::jsonb,
 updated_at timestamptz not null default now()
);
alter table public.marketplace_settings enable row level security;
grant select,insert,update,delete on public.marketplace_settings to authenticated;
grant select on public.marketplace_settings to anon;
create policy "marketplace settings admin" on public.marketplace_settings for all using(public.is_admin()) with check(public.is_admin());
create policy "public website settings read" on public.marketplace_settings for select using(setting_key='website');

create table if not exists public.vendor_support_tickets (
 id uuid primary key default gen_random_uuid(),
 vendor_id uuid not null references public.vendors(id) on delete cascade,
 subject text not null check(char_length(subject) between 3 and 160),
 message text not null check(char_length(message) between 10 and 5000),
 reference text,
 status text not null default 'open' check(status in ('open','in_progress','resolved','closed')),
 created_at timestamptz not null default now()
);
alter table public.vendor_support_tickets enable row level security;
grant select,insert on public.vendor_support_tickets to authenticated;
create policy "vendor support tickets owner read" on public.vendor_support_tickets for select using(public.owns_vendor(vendor_id) or public.is_admin());
create policy "vendor support tickets owner create" on public.vendor_support_tickets for insert with check(public.owns_vendor(vendor_id));

create policy "inventory vendor scoped read" on public.inventory for select
using(exists(select 1 from public.product_variants pv join public.products p on p.id=pv.product_id where pv.id=variant_id and (public.owns_vendor(p.vendor_id) or public.is_admin())));

create policy "approved vendor store settings" on public.vendors for update
using(owner_id=auth.uid() and status='approved')
with check(owner_id=auth.uid() and status='approved');

create policy "approved vendor product edits" on public.products for update
using(owns_vendor(vendor_id) and status='approved')
with check(owns_vendor(vendor_id) and status in ('approved','draft','pending','rejected'));

create or replace function public.prevent_vendor_product_self_approval()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is not null and not public.is_admin() and old.status<>'approved' and new.status='approved' then
   raise exception 'Products require admin approval';
 end if;
 return new;
end $$;
create trigger vendor_product_approval_guard before update of status on public.products
for each row execute function public.prevent_vendor_product_self_approval();

create or replace function public.admin_cancel_marketplace_order(p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare o public.orders%rowtype; oi record;
begin
 select * into o from public.orders where id=p_order_id for update;
 if not found then raise exception 'Order not found'; end if;
 if o.status in ('cancelled','returned','delivered','shipped') then raise exception 'This order cannot be cancelled in its current status'; end if;
 if exists(select 1 from public.payments p where p.order_id=p_order_id and p.status='paid' and (select coalesce(sum(r.amount),0) from public.refunds r where r.payment_id=p.id and r.status='succeeded')<p.amount) then raise exception 'Paid orders require a completed provider refund before cancellation'; end if;
 for oi in select variant_id,quantity from public.order_items where order_id=p_order_id and variant_id is not null for update loop
  if o.status='pending' then update public.inventory set reserved=greatest(0,reserved-oi.quantity),updated_at=now() where variant_id=oi.variant_id;
  else update public.inventory set quantity=quantity+oi.quantity,updated_at=now() where variant_id=oi.variant_id; end if;
 end loop;
 update public.orders set status='cancelled' where id=p_order_id;
 update public.order_items set status='cancelled' where order_id=p_order_id;
 insert into public.notifications(user_id,title,body) values(o.user_id,'Order cancelled','Your order has been cancelled by the marketplace support team.');
end $$;
revoke all on function public.admin_cancel_marketplace_order(uuid) from public,anon,authenticated;
grant execute on function public.admin_cancel_marketplace_order(uuid) to service_role;

create or replace function public.admin_marketplace_metrics()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if not public.is_admin() then raise exception 'Admin access required'; end if;
 select jsonb_build_object(
  'gmv',coalesce((select sum(total) from public.orders where status not in ('cancelled','returned')),0),
  'platform_revenue',coalesce((select sum(commission_amount) from public.order_items where status not in ('cancelled','returned')),0),
  'total_orders',(select count(*) from public.orders),
  'total_customers',(select count(*) from public.profiles),
  'active_vendors',(select count(*) from public.vendors where status='approved'),
  'pending_vendors',(select count(*) from public.vendors where status in ('pending','documents_requested')),
  'pending_products',(select count(*) from public.products where status='pending'),
  'order_status',(select coalesce(jsonb_object_agg(status::text,total),'{}'::jsonb) from (select status,count(*) total from public.orders group by status) x),
  'monthly_revenue',(select coalesce(jsonb_agg(jsonb_build_object('month',to_char(m.month_start,'Mon'),'amount',coalesce(p.amount,0)) order by m.month_start),'[]'::jsonb) from (select generate_series(date_trunc('month',now())-interval '5 months',date_trunc('month',now()),interval '1 month') month_start) m left join lateral (select sum(oi.commission_amount) amount from public.order_items oi join public.orders o on o.id=oi.order_id where oi.status not in ('cancelled','returned') and o.created_at>=m.month_start and o.created_at<m.month_start+interval '1 month') p on true)
 ) into result;
 return result;
end $$;
revoke all on function public.admin_marketplace_metrics() from public,anon;
grant execute on function public.admin_marketplace_metrics() to authenticated;

-- Keep checkout shipping aligned with the admin-configured free-shipping threshold.
create or replace function public.create_marketplace_order(p_user_id uuid,p_items jsonb,p_address jsonb,p_payment_method text,p_coupon_code text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare entry jsonb; v record; c public.coupons%rowtype; line_total numeric(12,2); sub numeric(12,2):=0; disc numeric(12,2):=0; ship numeric(12,2):=0; new_order uuid; count_items int:=0; free_shipping numeric(12,2):=2999;
begin
 if p_payment_method not in ('cod','razorpay') then raise exception 'Unsupported payment method'; end if;
 if p_user_id is null or coalesce(p_address->>'recipient_name','')='' or coalesce(p_address->>'phone','')='' or coalesce(p_address->>'line1','')='' or coalesce(p_address->>'postal_code','')='' then raise exception 'A complete delivery address is required'; end if;
 if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'The bag is empty'; end if;
 if (select count(distinct value->>'variant_id') from jsonb_array_elements(p_items))<>jsonb_array_length(p_items) then raise exception 'Remove duplicate bag items before checkout'; end if;
 select coalesce((select (value->>'free_shipping_threshold')::numeric from public.marketplace_settings where setting_key='website'),2999) into free_shipping;
 for entry in select value from jsonb_array_elements(p_items) loop
  if coalesce((entry->>'quantity')::int,0)<1 or (entry->>'quantity')::int>20 then raise exception 'Invalid quantity'; end if;
  select pv.id,pv.product_id,pv.sku,coalesce(pv.price,p.price) unit_price,pv.size,pv.color,p.vendor_id,p.name product_name,v.status vendor_status,coalesce(i.quantity,0)-coalesce(i.reserved,0) available into v
  from public.product_variants pv join public.products p on p.id=pv.product_id join public.vendors v on v.id=p.vendor_id join public.inventory i on i.variant_id=pv.id
  where pv.id=(entry->>'variant_id')::uuid and pv.is_active and p.status='approved' and v.status='approved' for update of pv,i;
  if not found then raise exception 'A product is unavailable'; end if;
  if v.available<(entry->>'quantity')::int then raise exception 'Insufficient stock for %',v.product_name; end if;
  sub:=sub+(v.unit_price*(entry->>'quantity')::int);count_items:=count_items+1;
 end loop;
 if p_coupon_code is not null and btrim(p_coupon_code)<>'' then
  select * into c from public.coupons where upper(code)=upper(btrim(p_coupon_code)) and is_active and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()) for update;
  if not found or sub<c.min_order or (c.usage_limit is not null and c.used_count>=c.usage_limit) then raise exception 'This coupon is invalid or unavailable'; end if;
  disc:=case when c.discount_type='percent' then sub*c.discount_value/100 else c.discount_value end;
  if c.max_discount is not null then disc:=least(disc,c.max_discount);end if;disc:=least(sub,greatest(0,disc));update public.coupons set used_count=used_count+1 where id=c.id;
 end if;
 ship:=case when sub>=free_shipping then 0 else 99 end;
 insert into public.orders(user_id,address_snapshot,status,subtotal,discount,shipping,total,coupon_id) values(p_user_id,p_address,case when p_payment_method='cod' then 'confirmed'::public.order_status else 'pending'::public.order_status end,sub,disc,ship,sub-disc+ship,c.id) returning id into new_order;
 for entry in select value from jsonb_array_elements(p_items) loop
  select pv.id,pv.product_id,pv.sku,coalesce(pv.price,p.price) unit_price,pv.size,pv.color,p.vendor_id,p.name product_name,v.commission_percent into v from public.product_variants pv join public.products p on p.id=pv.product_id join public.vendors v on v.id=p.vendor_id where pv.id=(entry->>'variant_id')::uuid;
  line_total:=v.unit_price*(entry->>'quantity')::int;
  insert into public.order_items(order_id,product_id,variant_id,vendor_id,product_name,sku,size,color,quantity,unit_price,commission_amount,status) values(new_order,v.product_id,v.id,v.vendor_id,v.product_name,v.sku,v.size,v.color,(entry->>'quantity')::int,v.unit_price,line_total*v.commission_percent/100,case when p_payment_method='cod' then 'confirmed'::public.order_status else 'pending'::public.order_status end);
  if p_payment_method='cod' then update public.inventory set quantity=quantity-(entry->>'quantity')::int,updated_at=now() where variant_id=v.id;else update public.inventory set reserved=reserved+(entry->>'quantity')::int,updated_at=now() where variant_id=v.id;end if;
 end loop;
 return jsonb_build_object('id',new_order,'total',sub-disc+ship,'discount',disc,'total_paise',((sub-disc+ship)*100)::int);
end $$;
revoke all on function public.create_marketplace_order(uuid,jsonb,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.create_marketplace_order(uuid,jsonb,jsonb,text,text) to service_role;
