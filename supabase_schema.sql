-- ============================================================================
--  Отбасы қаржысы — Supabase схемасын тексеру / түзету
--  ----------------------------------------------------------------------------
--  «Тұрақты» (fin_recurring) бөліміне жазғанда «жіберілмеді / не сохранено»
--  болып қатып қалса — бұл әдетте fin_recurring кестесінде баған жетіспейтінін
--  немесе RLS жазуға рұқсат бермейтінін білдіреді.
--
--  Бұл скриптті Supabase → SQL Editor-да БІР рет іске қосыңыз. Ол идемпотентті:
--  бар деректі өшірмейді, тек жетіспейтін кесте/бағанды қосады.
-- ============================================================================

-- 1) Тұрақты төлемдер кестесі (қосымша жазатын барлық баған) ------------------
create table if not exists public.fin_recurring (
  id           text primary key,
  household_id uuid not null references public.households(id) on delete cascade,
  kind         text,                      -- 'inc' | 'exp'
  active       boolean default true,
  day          integer,                   -- айдың күні (1..31)
  amount       numeric default 0,
  source       text,                      -- кіріс көзі (kind='inc')
  cat          text,                      -- шығын санаты (kind='exp')
  title        text,
  next_date    date,                      -- келесі есептелетін күн
  last_run     date,
  created_by   uuid,
  updated_at   timestamptz default now()
);

-- Кесте бұрыннан бар, бірақ баған жетіспеуі мүмкін — бәрін қауіпсіз қосамыз:
alter table public.fin_recurring add column if not exists kind       text;
alter table public.fin_recurring add column if not exists active     boolean default true;
alter table public.fin_recurring add column if not exists day        integer;
alter table public.fin_recurring add column if not exists amount     numeric default 0;
alter table public.fin_recurring add column if not exists source     text;
alter table public.fin_recurring add column if not exists cat        text;
alter table public.fin_recurring add column if not exists title      text;
alter table public.fin_recurring add column if not exists next_date  date;
alter table public.fin_recurring add column if not exists last_run   date;
alter table public.fin_recurring add column if not exists created_by uuid;
alter table public.fin_recurring add column if not exists updated_at timestamptz default now();

-- 2) Тұрақтыдан жасалатын жазбаларға recur_id бағаны қажет --------------------
--    (materializeRecurring expenses/fin_income кестелеріне recur_id жазады)
alter table public.expenses  add column if not exists recur_id text;
alter table public.fin_income add column if not exists recur_id text;

-- 3) Привилегии ролей — БЕЗ них Postgres вернёт "permission denied for table"
--    (проверяется ДО RLS, поэтому одних политик недостаточно). Таблицы,
--    созданные через SQL, не получают эти GRANT автоматически.
grant select, insert, update, delete on table public.fin_recurring to authenticated;
grant select, insert, update, delete on table public.fin_recurring to anon;

-- 4) RLS — отбасы мүшелері өз отбасының жазбаларын толық басқара алады ---------
--    Ескерту: басқа кестелеріңіздегі (expenses т.б.) саясат осыған ұқсас болуы
--    керек. Егер бөлек is_member() функцияңыз болса — соны қолданыңыз.
alter table public.fin_recurring enable row level security;

drop policy if exists "fin_recurring members select" on public.fin_recurring;
drop policy if exists "fin_recurring members write"  on public.fin_recurring;

create policy "fin_recurring members select" on public.fin_recurring
  for select using (
    household_id in (
      select hm.household_id from public.household_members hm
      where hm.user_id = auth.uid()
    )
  );

create policy "fin_recurring members write" on public.fin_recurring
  for all using (
    household_id in (
      select hm.household_id from public.household_members hm
      where hm.user_id = auth.uid()
    )
  ) with check (
    household_id in (
      select hm.household_id from public.household_members hm
      where hm.user_id = auth.uid()
    )
  );

-- 5) Realtime (қосымша live синхрон үшін; бұрыннан қосулы болса — қатесіз өтеді)
do $$
begin
  begin
    execute 'alter publication supabase_realtime add table public.fin_recurring';
  exception when duplicate_object then null;
              when undefined_object then null;
  end;
end $$;

-- Дайын. Енді қосымшада «Тұрақты» бөліміне жазба қосып көріңіз.
