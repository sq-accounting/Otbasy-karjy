-- ============================================================================
--  Отбасы қаржысы — RLS / қауіпсіздік аудиті
--  ----------------------------------------------------------------------------
--  Бұл жобада көп қосымшаның кестесі бір anon кілтпен тұр, ал ол кілт ашық
--  сайтта (GitHub Pages). Сондықтан ӘР кестеде RLS қосулы әрі дұрыс саясат
--  болуы ӨТЕ маңызды — әйтпесе бөтен біреу деректі оқып/жаза алады.
--
--  А-БӨЛІМ: тек ОҚИДЫ (ештеңе өзгертпейді) — қазіргі күйді көрсетеді.
--  Б-БӨЛІМ: қаржы кестелерін бекітеді (қажет болса ғана іске қосыңыз).
-- ============================================================================


-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  А-БӨЛІМ — АУДИТ (қауіпсіз, тек select). Нәтижесін маған жіберсеңіз болады ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- 1) Қай кестеде RLS қосулы / өшірулі (false = ҚАУІПТІ)
select n.nspname            as schema,
       c.relname            as table,
       c.relrowsecurity     as rls_enabled,
       c.relforcerowsecurity as rls_forced
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relrowsecurity asc, c.relname;   -- RLS өшірулілер ең жоғарыда

-- 2) Әр кестедегі саясаттар (политики) тізімі
select schemaname, tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- 3) anon / authenticated рөлдеріне берілген TABLE-привилегиялар
--    (anon-да артық INSERT/UPDATE/DELETE болмауы тиіс — әсіресе бөтен кестелерде)
select table_name, grantee, string_agg(privilege_type, ', ' order by privilege_type) as privileges
from information_schema.role_table_grants
where table_schema = 'public' and grantee in ('anon','authenticated')
group by table_name, grantee
order by table_name, grantee;


-- ╔══════════════════════════════════════════════════════════════════════════╗
-- ║  Б-БӨЛІМ — БЕКІТУ (қажет болса). Қаржы кестелеріне RLS + дұрыс саясат.      ║
-- ║  Идемпотентті: деректі өшірмейді. БІР рет іске қосуға болады.              ║
-- ╚══════════════════════════════════════════════════════════════════════════╝

-- Рекурсиясыз мүшелік тексеру (household_members саясаты өзіне сілтемесін деп)
create or replace function public.is_household_member(hh uuid)
returns boolean
language sql security definer stable
set search_path = public
as $$
  select exists (
    select 1 from public.household_members
    where household_id = hh and user_id = auth.uid()
  );
$$;

-- Барлық қаржы кестесіне household-негізді саясат орнату
do $$
declare t text;
begin
  foreach t in array array[
    'expenses','fin_income','fin_debts','fin_loans',
    'fin_goals','fin_recurring','fin_budgets','fin_categories'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('drop policy if exists "hh members all" on public.%I', t);
    execute format($f$
      create policy "hh members all" on public.%I
        for all
        using (public.is_household_member(household_id))
        with check (public.is_household_member(household_id))
    $f$, t);
  end loop;
end $$;

-- households кестесі: мүше өз отбасысын ғана көреді; өзгертуді тек RPC-мен
alter table public.households enable row level security;
grant select on public.households to authenticated;
drop policy if exists "hh visible to members" on public.households;
create policy "hh visible to members" on public.households
  for select using (public.is_household_member(id));

-- household_members: мүше өз отбасысының мүшелерін көреді
alter table public.household_members enable row level security;
grant select, insert, update, delete on public.household_members to authenticated;
drop policy if exists "members visible to members" on public.household_members;
create policy "members visible to members" on public.household_members
  for select using (public.is_household_member(household_id));

-- НАЗАР: жоғарыдағы household_members SELECT саясаты ғана. INSERT/UPDATE/DELETE-ті
-- тікелей рұқсат етпей, create_household / join_household / transfer_ownership /
-- delete_household RPC (security definer) арқылы ғана жасаған дұрыс — қазір солай.
-- Егер тікелей жазу қажет болса, жеке with check саясатын мұқият қосыңыз.

-- Дайын. Қайта А-БӨЛІМ-2-ні іске қосып, саясаттардың орнағанын тексеріңіз.
