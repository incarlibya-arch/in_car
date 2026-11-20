-- in car — قاعدة البيانات (Supabase / PostgreSQL)
-- شغّل هذا الملف كاملاً من: Supabase Dashboard ← SQL Editor ← New query ← Run
-- بعده شغّل wallet.sql. ولو عاودت تشغيل هذا الملف، عاود شغّل wallet.sql بعده (لأنه يحدّث دوال وصلاحيات منه).

create extension if not exists pgcrypto;

-- ============ الجداول ============

create table if not exists public.profiles (
  id           uuid primary key references auth.users on delete cascade,
  full_name    text not null,
  phone        text,
  role         text not null default 'passenger' check (role in ('passenger','driver')),
  car_model    text,
  car_color    text,
  plate        text,
  rating       numeric(2,1) not null default 5.0,
  rating_count int not null default 0,
  created_at   timestamptz not null default now()
);

create table if not exists public.rides (
  id               uuid primary key default gen_random_uuid(),
  passenger_id     uuid not null references public.profiles(id) on delete cascade,
  pickup_lat       double precision not null,
  pickup_lng       double precision not null,
  pickup_label     text,
  dropoff_lat      double precision not null,
  dropoff_lng      double precision not null,
  dropoff_label    text,
  distance_km      numeric(6,1),
  duration_min     int,
  offered_price    numeric(8,2) not null check (offered_price > 0),
  final_price      numeric(8,2),
  driver_id        uuid references public.profiles(id),
  status           text not null default 'open'
                   check (status in ('open','accepted','arrived','started','completed','cancelled')),
  passenger_rating int check (passenger_rating between 1 and 5),
  comment          text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index if not exists rides_status_idx on public.rides(status, created_at desc);
create index if not exists rides_driver_idx on public.rides(driver_id);

create table if not exists public.offers (
  id         uuid primary key default gen_random_uuid(),
  ride_id    uuid not null references public.rides(id) on delete cascade,
  driver_id  uuid not null references public.profiles(id) on delete cascade,
  price      numeric(8,2) not null check (price > 0),
  eta_min    int,
  status     text not null default 'pending'
             check (status in ('pending','accepted','declined','withdrawn')),
  created_at timestamptz not null default now(),
  unique (ride_id, driver_id)
);

create table if not exists public.driver_locations (
  driver_id  uuid primary key references public.profiles(id) on delete cascade,
  lat        double precision not null,
  lng        double precision not null,
  is_online  boolean not null default false,
  updated_at timestamptz not null default now()
);

-- ============ دوال مساعدة ============

create or replace function public.is_driver() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'driver');
$$;

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
drop trigger if exists rides_touch on public.rides;
create trigger rides_touch before update on public.rides
for each row execute function public.touch_updated_at();

-- قبول عرض: ذرّي، يمنع قبول عرضين لنفس الرحلة
create or replace function public.accept_offer(p_offer_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare o offers%rowtype;
begin
  select * into o from offers where id = p_offer_id and status = 'pending';
  if not found then raise exception 'العرض غير متاح'; end if;

  update rides set status = 'accepted', driver_id = o.driver_id, final_price = o.price
   where id = o.ride_id and passenger_id = auth.uid() and status = 'open';
  if not found then raise exception 'الرحلة لم تعد مفتوحة'; end if;

  update offers set status = 'accepted' where id = o.id;
  update offers set status = 'declined' where ride_id = o.ride_id and id <> o.id and status = 'pending';
end $$;

-- السائق يحدّث حالة الرحلة بالترتيب فقط
create or replace function public.advance_ride(p_ride_id uuid, p_status text) returns void
language plpgsql security definer set search_path = public as $$
declare cur text;
begin
  select status into cur from rides where id = p_ride_id and driver_id = auth.uid() for update;
  if not found then raise exception 'ليست رحلتك'; end if;
  if not ((cur = 'accepted' and p_status in ('arrived','cancelled'))
       or (cur = 'arrived'  and p_status in ('started','cancelled'))
       or (cur = 'started'  and p_status = 'completed')) then
    raise exception 'انتقال غير مسموح من % إلى %', cur, p_status;
  end if;
  update rides set status = p_status where id = p_ride_id;
end $$;

-- الراكب يقيّم السائق بعد انتهاء الرحلة
create or replace function public.rate_ride(p_ride_id uuid, p_stars int) returns void
language plpgsql security definer set search_path = public as $$
declare d uuid;
begin
  update rides set passenger_rating = p_stars
   where id = p_ride_id and passenger_id = auth.uid() and status = 'completed' and passenger_rating is null
   returning driver_id into d;
  if d is null then raise exception 'لا يمكن التقييم'; end if;
  update profiles
     set rating = round(((rating * rating_count) + p_stars)::numeric / (rating_count + 1), 1),
         rating_count = rating_count + 1
   where id = d;
end $$;

-- ============ الصلاحيات (RLS) ============

alter table public.profiles         enable row level security;
alter table public.rides            enable row level security;
alter table public.offers           enable row level security;
alter table public.driver_locations enable row level security;

-- profiles
drop policy if exists "profiles read" on public.profiles;
create policy "profiles read" on public.profiles for select to authenticated using (true);
drop policy if exists "profiles insert own" on public.profiles;
create policy "profiles insert own" on public.profiles for insert to authenticated with check (id = auth.uid());
drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- rides
drop policy if exists "rides read" on public.rides;
create policy "rides read" on public.rides for select to authenticated using (
  passenger_id = auth.uid() or driver_id = auth.uid() or (status = 'open' and public.is_driver())
);
drop policy if exists "rides insert" on public.rides;
create policy "rides insert" on public.rides for insert to authenticated
  with check (passenger_id = auth.uid() and status = 'open');
-- الراكب يعدّل سعره أو يلغي طلبه وهو مفتوح فقط (القبول وتغيير الحالة عبر الدوال)
drop policy if exists "rides passenger update" on public.rides;
create policy "rides passenger update" on public.rides for update to authenticated
  using (passenger_id = auth.uid() and status = 'open')
  with check (passenger_id = auth.uid() and status in ('open','cancelled') and driver_id is null);

-- offers
drop policy if exists "offers read" on public.offers;
create policy "offers read" on public.offers for select to authenticated using (
  driver_id = auth.uid()
  or exists (select 1 from rides r where r.id = ride_id and r.passenger_id = auth.uid())
);
drop policy if exists "offers insert" on public.offers;
create policy "offers insert" on public.offers for insert to authenticated with check (
  driver_id = auth.uid() and public.is_driver()
  and exists (select 1 from rides r where r.id = ride_id and r.status = 'open' and r.passenger_id <> auth.uid())
);
drop policy if exists "offers driver update" on public.offers;
create policy "offers driver update" on public.offers for update to authenticated
  using (driver_id = auth.uid() and status = 'pending')
  with check (driver_id = auth.uid() and status in ('pending','withdrawn'));
drop policy if exists "offers passenger decline" on public.offers;
create policy "offers passenger decline" on public.offers for update to authenticated
  using (exists (select 1 from rides r where r.id = ride_id and r.passenger_id = auth.uid()))
  with check (status = 'declined');

-- driver_locations
drop policy if exists "locations read" on public.driver_locations;
create policy "locations read" on public.driver_locations for select to authenticated using (true);
drop policy if exists "locations upsert own" on public.driver_locations;
create policy "locations upsert own" on public.driver_locations for insert to authenticated
  with check (driver_id = auth.uid() and public.is_driver());
drop policy if exists "locations update own" on public.driver_locations;
create policy "locations update own" on public.driver_locations for update to authenticated
  using (driver_id = auth.uid()) with check (driver_id = auth.uid());

grant execute on function public.accept_offer(uuid)        to authenticated;
grant execute on function public.advance_ride(uuid, text)  to authenticated;
grant execute on function public.rate_ride(uuid, int)      to authenticated;

-- ============ التحديث المباشر (Realtime) ============
do $$ begin
  begin alter publication supabase_realtime add table public.rides;            exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.offers;           exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.driver_locations; exception when duplicate_object then null; end;
end $$;
