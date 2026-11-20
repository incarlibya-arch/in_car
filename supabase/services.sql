-- in car — الخدمات: بين المدن، الطرود، البضائع، الإشعارات، المحادثة،
-- التحقق من الوثائق، الطوارئ، والحجز المسبق.
-- الترتيب: schema.sql ← wallet.sql ← services.sql

-- ============ 1-2) أنواع الخدمات والحجز المسبق ============

alter table public.rides add column if not exists service text not null default 'city'
  check (service in ('city','intercity','courier','freight'));
alter table public.rides add column if not exists details jsonb not null default '{}'::jsonb;
alter table public.rides add column if not exists scheduled_at timestamptz;
alter table public.rides add column if not exists seats int check (seats between 1 and 8);
alter table public.rides add column if not exists reminded boolean not null default false;
create index if not exists rides_scheduled_idx on public.rides(scheduled_at) where scheduled_at is not null;

alter table public.profiles add column if not exists services text[] not null default '{city}';
alter table public.profiles add column if not exists vehicle_type text not null default 'car'
  check (vehicle_type in ('car','van','pickup','small_truck','large_truck'));

-- ============ 5) التحقق من السائقين ============

alter table public.profiles add column if not exists driver_status text not null default 'pending'
  check (driver_status in ('pending','approved','rejected'));
alter table public.profiles add column if not exists driver_note text;

alter table public.app_settings add column if not exists require_verification boolean not null default true;
alter table public.app_settings add column if not exists emergency_phone text not null default '';
alter table public.app_settings add column if not exists support_phone text not null default '';

-- يمنع المستخدم يعدّل تقييمه أو حالة توثيقه بنفسه
create or replace function public.protect_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and auth.uid() = new.id and not is_admin() then
    if tg_op = 'INSERT' then
      new.rating := 5.0; new.rating_count := 0; new.driver_status := 'pending'; new.driver_note := null;
    else
      new.rating := old.rating; new.rating_count := old.rating_count;
      new.driver_status := old.driver_status; new.driver_note := old.driver_note;
      -- لو غيّر بيانات السيارة أو تحوّل لسائق، يرجع للمراجعة
      if new.role = 'driver' and (old.role <> 'driver' or new.plate is distinct from old.plate
          or new.car_model is distinct from old.car_model or new.vehicle_type is distinct from old.vehicle_type) then
        new.driver_status := 'pending';
      end if;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_protect on public.profiles;
create trigger profiles_protect before insert or update on public.profiles
for each row execute function public.protect_profile();

create table if not exists public.driver_documents (
  id          uuid primary key default gen_random_uuid(),
  driver_id   uuid not null references public.profiles(id) on delete cascade,
  doc_type    text not null check (doc_type in ('license','id_card','registration','car_photo')),
  path        text not null,           -- المسار داخل مخزن driver-docs
  status      text not null default 'pending' check (status in ('pending','approved','rejected')),
  uploaded_at timestamptz not null default now(),
  unique (driver_id, doc_type)
);

create or replace function public.admin_set_driver_status(p_driver uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للإدارة فقط'; end if;
  if p_status not in ('pending','approved','rejected') then raise exception 'حالة غير صحيحة'; end if;
  update profiles set driver_status = p_status, driver_note = p_note where id = p_driver and role = 'driver';
  if not found then raise exception 'السائق غير موجود'; end if;
  update driver_documents set status = case when p_status = 'approved' then 'approved'
                                            when p_status = 'rejected' then 'rejected' else status end
   where driver_id = p_driver;
  insert into notifications (user_id, title, body, data)
  values (p_driver,
          case p_status when 'approved' then 'تم توثيق حسابك' when 'rejected' then 'لم يتم قبول وثائقك' else 'حسابك قيد المراجعة' end,
          coalesce(p_note, case p_status when 'approved' then 'تقدر تبدأ تستقبل الطلبات توا' else 'راجع وثائقك من صفحة حسابي' end),
          jsonb_build_object('type','driver_status'));
end $$;

create or replace function public.driver_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select not s.require_verification
      or exists (select 1 from profiles where id = auth.uid() and driver_status = 'approved')
  from app_settings s where s.id = 1;
$$;

-- العروض: سائق + موثّق + رصيد كافي + الرحلة مفتوحة
drop policy if exists "offers insert" on public.offers;
create policy "offers insert" on public.offers for insert to authenticated with check (
  driver_id = auth.uid() and public.is_driver() and public.driver_approved() and public.driver_can_work()
  and exists (select 1 from rides r where r.id = ride_id and r.status = 'open' and r.passenger_id <> auth.uid())
);

-- ============ 3) الإشعارات ============

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  title      text not null,
  body       text not null,
  data       jsonb not null default '{}'::jsonb,
  read       boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications(user_id, created_at desc);

create table if not exists public.device_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  platform   text,
  updated_at timestamptz not null default now()
);

-- رحلة جديدة ← السواقين المتصلين اللي يقدموا نفس الخدمة، في حدود 15 كم (أو أي مكان لبين المدن)
create or replace function public.notify_new_ride() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notifications (user_id, title, body, data)
  select p.id,
         case new.service when 'intercity' then 'طلب سفر جديد' when 'courier' then 'طلب توصيل طرد'
                          when 'freight' then 'طلب نقل بضاعة' else 'طلب مشوار جديد' end,
         coalesce(new.pickup_label,'') || ' ← ' || coalesce(new.dropoff_label,'') || ' · ' || new.offered_price || ' د.ل',
         jsonb_build_object('type','new_ride','ride_id',new.id)
    from profiles p
    join driver_locations l on l.driver_id = p.id and l.is_online and l.updated_at > now() - interval '10 minutes'
   where p.role = 'driver' and p.id <> new.passenger_id and new.service = any(p.services)
     and (new.service = 'intercity'
          or (abs(l.lat - new.pickup_lat) < 0.14 and abs(l.lng - new.pickup_lng) < 0.16));
  return new;
end $$;
drop trigger if exists rides_notify_new on public.rides;
create trigger rides_notify_new after insert on public.rides
for each row execute function public.notify_new_ride();

-- عرض جديد ← الراكب
create or replace function public.notify_new_offer() returns trigger
language plpgsql security definer set search_path = public as $$
declare r rides%rowtype; d text;
begin
  if new.status <> 'pending' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'pending' and old.price = new.price then return new; end if;
  select * into r from rides where id = new.ride_id;
  select full_name into d from profiles where id = new.driver_id;
  insert into notifications (user_id, title, body, data)
  values (r.passenger_id, 'عرض جديد من ' || coalesce(d,'سائق'), new.price || ' د.ل',
          jsonb_build_object('type','offer','ride_id',r.id));
  return new;
end $$;
drop trigger if exists offers_notify on public.offers;
create trigger offers_notify after insert or update on public.offers
for each row execute function public.notify_new_offer();

-- تغيّر حالة الرحلة ← الطرف الثاني
create or replace function public.notify_ride_status() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = old.status then return new; end if;
  if new.status = 'accepted' and new.driver_id is not null then
    insert into notifications (user_id, title, body, data) values (new.driver_id, 'الراكب قبل عرضك',
      case when new.scheduled_at is not null and new.scheduled_at > now() + interval '30 minutes'
           then 'رحلة محجوزة: ' || to_char(new.scheduled_at at time zone 'Africa/Tripoli', 'YYYY-MM-DD HH24:MI')
           else 'توجّه للراكب: ' || coalesce(new.pickup_label,'') end,
      jsonb_build_object('type','accepted','ride_id',new.id));
  elsif new.status = 'arrived' then
    insert into notifications (user_id, title, body, data)
    values (new.passenger_id, 'السائق وصل', 'السائق ينتظر فيك', jsonb_build_object('type','arrived','ride_id',new.id));
  elsif new.status = 'completed' then
    insert into notifications (user_id, title, body, data)
    values (new.passenger_id, 'وصلت بالسلامة', 'قيّم السائق من التطبيق', jsonb_build_object('type','completed','ride_id',new.id));
  elsif new.status = 'cancelled' then
    insert into notifications (user_id, title, body, data)
    select u, 'انلغت الرحلة', coalesce(new.pickup_label,'') || ' ← ' || coalesce(new.dropoff_label,''),
           jsonb_build_object('type','cancelled','ride_id',new.id)
      from unnest(array[new.passenger_id, new.driver_id]) u
     where u is not null and u <> auth.uid();
  end if;
  return new;
end $$;
drop trigger if exists rides_notify_status on public.rides;
create trigger rides_notify_status after update of status on public.rides
for each row execute function public.notify_ride_status();

-- الشحن ← السائق
create or replace function public.notify_topup() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status <> old.status and new.status in ('approved','rejected') then
    insert into notifications (user_id, title, body, data)
    values (new.driver_id,
            case when new.status = 'approved' then 'تم شحن رصيدك' else 'تم رفض طلب الشحن' end,
            new.amount || ' د.ل' || coalesce(' · ' || new.admin_note, ''),
            jsonb_build_object('type','topup'));
  end if;
  return new;
end $$;
drop trigger if exists topup_notify on public.topup_requests;
create trigger topup_notify after update on public.topup_requests
for each row execute function public.notify_topup();

-- ============ 4) المحادثة ============

create table if not exists public.messages (
  id         uuid primary key default gen_random_uuid(),
  ride_id    uuid not null references public.rides(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index if not exists messages_ride_idx on public.messages(ride_id, created_at);

create or replace function public.is_ride_party(p_ride uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from rides where id = p_ride and (passenger_id = auth.uid() or driver_id = auth.uid()));
$$;

create or replace function public.notify_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare r rides%rowtype; n text;
begin
  select * into r from rides where id = new.ride_id;
  select full_name into n from profiles where id = new.sender_id;
  insert into notifications (user_id, title, body, data)
  select u, 'رسالة من ' || coalesce(n,''), left(new.body, 120), jsonb_build_object('type','message','ride_id',r.id)
    from unnest(array[r.passenger_id, r.driver_id]) u
   where u is not null and u <> new.sender_id;
  return new;
end $$;
drop trigger if exists messages_notify on public.messages;
create trigger messages_notify after insert on public.messages
for each row execute function public.notify_message();

-- ============ 6) الطوارئ ============

create table if not exists public.sos_alerts (
  id         uuid primary key default gen_random_uuid(),
  ride_id    uuid references public.rides(id) on delete set null,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  lat        double precision,
  lng        double precision,
  resolved   boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.notify_sos() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notifications (user_id, title, body, data)
  select a.user_id, 'تنبيه طوارئ!', coalesce((select full_name from profiles where id = new.user_id),'مستخدم') || ' ضغط زر الطوارئ',
         jsonb_build_object('type','sos','sos_id',new.id,'ride_id',new.ride_id)
    from admins a;
  return new;
end $$;
drop trigger if exists sos_notify on public.sos_alerts;
create trigger sos_notify after insert on public.sos_alerts
for each row execute function public.notify_sos();

-- ============ 7) تذكير الرحلات المحجوزة (كل 5 دقايق) ============

create or replace function public.remind_scheduled_rides() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with due as (
    update rides set reminded = true
     where status = 'accepted' and not reminded and scheduled_at is not null
       and scheduled_at between now() and now() + interval '30 minutes'
    returning id, passenger_id, driver_id, pickup_label, scheduled_at
  )
  insert into notifications (user_id, title, body, data)
  select u, 'تذكير: رحلتك بعد أقل من 30 دقيقة',
         coalesce(d.pickup_label,'') || ' · ' || to_char(d.scheduled_at at time zone 'Africa/Tripoli','HH24:MI'),
         jsonb_build_object('type','reminder','ride_id',d.id)
    from due d, unnest(array[d.passenger_id, d.driver_id]) u
   where u is not null;
  get diagnostics n = row_count;
  return n;
end $$;
revoke execute on function public.remind_scheduled_rides() from public, anon, authenticated;

-- يشغّل التذكير تلقائياً لو pg_cron متوفر (فعّله من Database ← Extensions ← pg_cron)
do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('incar-reminders', '*/5 * * * *', 'select public.remind_scheduled_rides()');
exception when others then
  raise notice 'pg_cron غير متوفر: فعّله من Database ← Extensions ثم أعد تشغيل هذا الملف';
end $$;

-- ============ الصلاحيات (RLS) ============

alter table public.driver_documents enable row level security;
alter table public.notifications    enable row level security;
alter table public.device_tokens    enable row level security;
alter table public.messages         enable row level security;
alter table public.sos_alerts       enable row level security;

-- إخفاء أرقام الهواتف: الكل يقرأ الملفات، لكن الرقم يظهر بس للطرفين في رحلة نشطة (عبر الدالة)
create or replace function public.party_phone(p_user uuid) returns text
language sql stable security definer set search_path = public as $$
  select p.phone from profiles p
   where p.id = p_user and (p_user = auth.uid() or is_admin() or exists (
     select 1 from rides r where r.status in ('accepted','arrived','started')
       and ((r.passenger_id = auth.uid() and r.driver_id = p_user) or (r.driver_id = auth.uid() and r.passenger_id = p_user))));
$$;
revoke select on public.profiles from anon, authenticated;
grant select (id, full_name, role, car_model, car_color, plate, rating, rating_count, created_at,
              services, vehicle_type, driver_status, driver_note) on public.profiles to authenticated;

drop policy if exists "docs read" on public.driver_documents;
create policy "docs read" on public.driver_documents for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());
drop policy if exists "docs insert" on public.driver_documents;
create policy "docs insert" on public.driver_documents for insert to authenticated
  with check (driver_id = auth.uid() and status = 'pending');
drop policy if exists "docs update" on public.driver_documents;
create policy "docs update" on public.driver_documents for update to authenticated
  using (driver_id = auth.uid()) with check (driver_id = auth.uid() and status = 'pending');

drop policy if exists "notif read" on public.notifications;
create policy "notif read" on public.notifications for select to authenticated using (user_id = auth.uid());
drop policy if exists "notif mark read" on public.notifications;
create policy "notif mark read" on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "tokens own" on public.device_tokens;
create policy "tokens own" on public.device_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "messages read" on public.messages;
create policy "messages read" on public.messages for select to authenticated using (public.is_ride_party(ride_id));
drop policy if exists "messages send" on public.messages;
create policy "messages send" on public.messages for insert to authenticated with check (
  sender_id = auth.uid() and exists (
    select 1 from rides r where r.id = ride_id and r.status in ('accepted','arrived','started')
      and (r.passenger_id = auth.uid() or r.driver_id = auth.uid()))
);

drop policy if exists "sos insert" on public.sos_alerts;
create policy "sos insert" on public.sos_alerts for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "sos read" on public.sos_alerts;
create policy "sos read" on public.sos_alerts for select to authenticated using (user_id = auth.uid() or public.is_admin());
drop policy if exists "sos resolve" on public.sos_alerts;
create policy "sos resolve" on public.sos_alerts for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- الإدارة تقرأ كل الرحلات (للمتابعة والطوارئ)
drop policy if exists "rides admin read" on public.rides;
create policy "rides admin read" on public.rides for select to authenticated using (public.is_admin());

grant execute on function public.driver_approved()                          to authenticated;
grant execute on function public.admin_set_driver_status(uuid, text, text)  to authenticated;
grant execute on function public.is_ride_party(uuid)                        to authenticated;
grant execute on function public.party_phone(uuid)                          to authenticated;

-- الإدارة: البحث عن سائق برقم هاتفه
create or replace function public.admin_find_driver(p_phone text) returns setof public.profiles
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للإدارة فقط'; end if;
  return query select * from profiles
   where role = 'driver' and (phone = p_phone or phone = ltrim(p_phone, '+')) limit 1;
end $$;
grant execute on function public.admin_find_driver(text) to authenticated;

-- الإدارة: السواقين اللي ينتظروا المراجعة
create or replace function public.admin_pending_drivers() returns setof public.profiles
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للإدارة فقط'; end if;
  return query select * from profiles where role = 'driver' and driver_status = 'pending' order by created_at;
end $$;
grant execute on function public.admin_pending_drivers() to authenticated;

-- ============ مخزن الوثائق (Storage) ============
insert into storage.buckets (id, name, public) values ('driver-docs', 'driver-docs', false)
on conflict (id) do nothing;

drop policy if exists "driver docs upload" on storage.objects;
create policy "driver docs upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'driver-docs' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "driver docs replace" on storage.objects;
create policy "driver docs replace" on storage.objects for update to authenticated
  using (bucket_id = 'driver-docs' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "driver docs read" on storage.objects;
create policy "driver docs read" on storage.objects for select to authenticated
  using (bucket_id = 'driver-docs' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

-- ============ التحديث المباشر ============
do $$ begin
  begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.messages;      exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.sos_alerts;    exception when duplicate_object then null; end;
end $$;
