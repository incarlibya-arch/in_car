-- in car — المحفظة والعمولة
-- شغّل هذا الملف بعد schema.sql، من SQL Editor ← New query ← Run

-- ============ الإعدادات العامة ============

create table if not exists public.app_settings (
  id              int primary key default 1 check (id = 1),
  commission_rate numeric(5,4) not null default 0 check (commission_rate between 0 and 0.5), -- 0.07 = 7%
  min_balance     numeric(8,2) not null default 0,   -- أقل رصيد يسمح للسائق يقدّم عروض
  free_until      timestamptz,                        -- فترة بدون عمولة (للإطلاق)
  topup_info      text not null default 'اشحن رصيدك عند مكتب in car أو بتحويل مصرفي، وبعدها ابعت رقم العملية من هنا.'
);
insert into public.app_settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.admins (
  user_id uuid primary key references auth.users on delete cascade
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where user_id = auth.uid());
$$;

-- ============ المحفظة ============

create table if not exists public.driver_wallets (
  driver_id  uuid primary key references public.profiles(id) on delete cascade,
  balance    numeric(10,2) not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.wallet_transactions (
  id         uuid primary key default gen_random_uuid(),
  driver_id  uuid not null references public.profiles(id) on delete cascade,
  amount     numeric(10,2) not null,           -- موجب = شحن، سالب = عمولة
  kind       text not null check (kind in ('topup','commission','adjustment','refund')),
  ride_id    uuid references public.rides(id) on delete set null,
  note       text,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index if not exists wallet_tx_driver_idx on public.wallet_transactions(driver_id, created_at desc);

create table if not exists public.topup_requests (
  id         uuid primary key default gen_random_uuid(),
  driver_id  uuid not null references public.profiles(id) on delete cascade,
  amount     numeric(10,2) not null check (amount > 0 and amount <= 5000),
  method     text not null check (method in ('cash_agent','bank_transfer','sadad','mobicash','other')),
  reference  text,
  status     text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid
);
create index if not exists topup_status_idx on public.topup_requests(status, created_at);

alter table public.rides add column if not exists commission numeric(8,2);

-- ============ دوال المحفظة ============

-- داخلية: تضيف حركة وتحدّث الرصيد في خطوة وحدة
create or replace function public.wallet_apply(p_driver uuid, p_amount numeric, p_kind text, p_ride uuid, p_note text)
returns numeric language plpgsql security definer set search_path = public as $$
declare b numeric;
begin
  insert into driver_wallets (driver_id, balance) values (p_driver, p_amount)
  on conflict (driver_id) do update set balance = driver_wallets.balance + excluded.balance, updated_at = now()
  returning balance into b;
  insert into wallet_transactions (driver_id, amount, kind, ride_id, note, created_by)
  values (p_driver, p_amount, p_kind, p_ride, p_note, auth.uid());
  return b;
end $$;
revoke execute on function public.wallet_apply(uuid, numeric, text, uuid, text) from public, anon, authenticated;

-- هل يقدر السائق الحالي يقدّم عروض؟
create or replace function public.driver_can_work() returns boolean
language sql stable security definer set search_path = public as $$
  select s.commission_rate = 0
      or (s.free_until is not null and s.free_until > now())
      or coalesce((select balance from driver_wallets where driver_id = auth.uid()), 0) >= s.min_balance
  from app_settings s where s.id = 1;
$$;

-- العروض: نفس شروط schema.sql + الرصيد كافي
drop policy if exists "offers insert" on public.offers;
create policy "offers insert" on public.offers for insert to authenticated with check (
  driver_id = auth.uid() and public.is_driver() and public.driver_can_work()
  and exists (select 1 from rides r where r.id = ride_id and r.status = 'open' and r.passenger_id <> auth.uid())
);

-- تحديث حالة الرحلة + خصم العمولة عند الإنهاء
create or replace function public.advance_ride(p_ride_id uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
declare
  cur text;
  fp  numeric;
  s   app_settings%rowtype;
  c   numeric := 0;
begin
  select status, coalesce(final_price, offered_price) into cur, fp
    from rides where id = p_ride_id and driver_id = auth.uid() for update;
  if not found then raise exception 'ليست رحلتك'; end if;
  if not ((cur = 'accepted' and p_status in ('arrived','cancelled'))
       or (cur = 'arrived'  and p_status in ('started','cancelled'))
       or (cur = 'started'  and p_status = 'completed')) then
    raise exception 'انتقال غير مسموح من % إلى %', cur, p_status;
  end if;

  if p_status = 'completed' then
    select * into s from app_settings where id = 1;
    if s.commission_rate > 0 and (s.free_until is null or s.free_until <= now()) then
      c := round(fp * s.commission_rate, 2);
    end if;
    update rides set status = 'completed', commission = c where id = p_ride_id;
    if c > 0 then
      perform wallet_apply(auth.uid(), -c, 'commission', p_ride_id, null);
    end if;
  else
    update rides set status = p_status where id = p_ride_id;
  end if;
end $$;

-- الإدارة: قبول أو رفض طلب شحن
create or replace function public.admin_decide_topup(p_request_id uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare r topup_requests%rowtype;
begin
  if not is_admin() then raise exception 'للإدارة فقط'; end if;
  select * into r from topup_requests where id = p_request_id and status = 'pending' for update;
  if not found then raise exception 'الطلب غير موجود أو تمت معالجته'; end if;
  update topup_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         admin_note = p_note, decided_at = now(), decided_by = auth.uid()
   where id = r.id;
  if p_approve then
    perform wallet_apply(r.driver_id, r.amount, 'topup', null, coalesce(p_note, r.method || ' ' || coalesce(r.reference, '')));
  end if;
end $$;

-- الإدارة: تعديل رصيد سائق يدوياً (شحن من المكتب أو تصحيح)
create or replace function public.admin_adjust_wallet(p_driver uuid, p_amount numeric, p_note text)
returns numeric language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للإدارة فقط'; end if;
  if p_amount = 0 then raise exception 'المبلغ لازم يكون غير صفر'; end if;
  return wallet_apply(p_driver, p_amount, case when p_amount > 0 then 'topup' else 'adjustment' end, null, p_note);
end $$;

grant execute on function public.is_admin()                                 to authenticated;
grant execute on function public.driver_can_work()                          to authenticated;
grant execute on function public.advance_ride(uuid, text)                   to authenticated;
grant execute on function public.admin_decide_topup(uuid, boolean, text)    to authenticated;
grant execute on function public.admin_adjust_wallet(uuid, numeric, text)   to authenticated;

-- ============ الصلاحيات (RLS) ============

alter table public.app_settings        enable row level security;
alter table public.admins              enable row level security;
alter table public.driver_wallets      enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.topup_requests      enable row level security;

drop policy if exists "settings read" on public.app_settings;
create policy "settings read" on public.app_settings for select to authenticated using (true);
drop policy if exists "settings admin update" on public.app_settings;
create policy "settings admin update" on public.app_settings for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admins read own" on public.admins;
create policy "admins read own" on public.admins for select to authenticated using (user_id = auth.uid());

drop policy if exists "wallet read" on public.driver_wallets;
create policy "wallet read" on public.driver_wallets for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());

drop policy if exists "tx read" on public.wallet_transactions;
create policy "tx read" on public.wallet_transactions for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());

drop policy if exists "topup read" on public.topup_requests;
create policy "topup read" on public.topup_requests for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());
drop policy if exists "topup insert" on public.topup_requests;
create policy "topup insert" on public.topup_requests for insert to authenticated
  with check (driver_id = auth.uid() and status = 'pending' and public.is_driver());

-- ============ التحديث المباشر ============
do $$ begin
  begin alter publication supabase_realtime add table public.driver_wallets; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.topup_requests; exception when duplicate_object then null; end;
end $$;

-- ============ أول مدير ============
-- بعد ما تسجّل دخول في التطبيق برقمك، شغّل السطر هذا (بدّل الرقم برقمك، بدون +):
-- insert into public.admins (user_id) select id from auth.users where phone = '218912345678';
