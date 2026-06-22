-- ============================================================================
--  Отбасы қаржысы — өзіндік шығын санаттары (fin_categories)
--  «Баптау → Шығын санаттары» бөлімі осы кестеге сақтайды.
--  Supabase → SQL Editor-да БІР рет іске қосыңыз. Идемпотентті.
-- ============================================================================

create table if not exists public.fin_categories (
  household_id uuid not null references public.households(id) on delete cascade,
  key          text not null,                 -- қосымша жасайтын тұрақты кілт (uid)
  name         text,
  emoji        text,
  color        text,
  sort         bigint default 0,
  updated_at   timestamptz default now(),
  primary key (household_id, key)
);

-- Жетіспейтін бағандарды қауіпсіз қосу (кесте бұрыннан болса)
alter table public.fin_categories add column if not exists name       text;
alter table public.fin_categories add column if not exists emoji      text;
alter table public.fin_categories add column if not exists color      text;
alter table public.fin_categories add column if not exists sort       bigint default 0;
alter table public.fin_categories add column if not exists updated_at timestamptz default now();

-- Рөл привилегиялары (БҰЛ БОЛМАСА "permission denied for table" қатесі шығады)
grant select, insert, update, delete on table public.fin_categories to authenticated;
grant select, insert, update, delete on table public.fin_categories to anon;

-- RLS — мүше өз отбасының санаттарын ғана басқарады
alter table public.fin_categories enable row level security;
drop policy if exists "fin_categories members all" on public.fin_categories;
create policy "fin_categories members all" on public.fin_categories
  for all
  using (
    household_id in (select household_id from public.household_members where user_id = auth.uid())
  ) with check (
    household_id in (select household_id from public.household_members where user_id = auth.uid())
  );

-- Realtime (қаласаңыз; бұрыннан қосулы болса қатесіз өтеді)
do $$
begin
  begin execute 'alter publication supabase_realtime add table public.fin_categories';
  exception when duplicate_object then null; when undefined_object then null; end;
end $$;
