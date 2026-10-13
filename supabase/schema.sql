-- Finance app — database schema.
--
-- Run in the Supabase SQL Editor. Every statement is idempotent and additive,
-- so re-running it is safe and existing expenses are preserved.
--
-- There is no profiles table: the registered name lives in the auth user's
-- metadata (`raw_user_meta_data -> full_name`), set by the app at sign-up.

-- ---------------------------------------------------------------- expenses ---
create table if not exists public.expenses (
  id         uuid primary key default gen_random_uuid(),
  -- Defaults to the caller, so a client can never insert on someone else's
  -- behalf even if it forgets to send the column.
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  amount     numeric(12, 2) not null check (amount > 0),
  category   text not null check (
               category in ('groceries', 'fuel', 'dining', 'bills',
                            'rent', 'health', 'shopping', 'other')
             ),
  spent_on   date not null,
  note       text not null default '',
  created_at timestamptz not null default now()
);

-- What was bought ("Chicken", "Petrol"). Drives the autocomplete: the app
-- learns names and their usual prices from this column.
alter table public.expenses
  add column if not exists item text not null default '';

-- The app always reads one user's expenses newest-first.
create index if not exists expenses_user_spent_on_idx
  on public.expenses (user_id, spent_on desc, created_at desc);

-- Supports "what do I buy most" and the item suggestions.
create index if not exists expenses_user_item_idx
  on public.expenses (user_id, item);

-- ----------------------------------------------------------------- budgets ---
-- One monthly limit per category, per user.
create table if not exists public.budgets (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  category   text not null check (
               category in ('groceries', 'fuel', 'dining', 'bills',
                            'rent', 'health', 'shopping', 'other')
             ),
  monthly_limit numeric(12, 2) not null check (monthly_limit > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, category)
);

-- ----------------------------------------------------------- monthly pay ---
-- What was earned in a given month. One row per month, so a raise changes
-- future months without rewriting the savings history of past ones. A month
-- with no row inherits the most recent earlier month's figure (done in the app).
create table if not exists public.monthly_income (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  -- Always the first of the month.
  month      date not null,
  amount     numeric(12, 2) not null check (amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, month)
);

create index if not exists monthly_income_user_month_idx
  on public.monthly_income (user_id, month desc);

-- ---------------------------------------------------------- family members ---
-- The people in one household. The whole family shares a single login, so a
-- member is a label, not an account: no password, no permissions, nothing to
-- sign in as. It answers "who spent this", not "who is allowed to".
create table if not exists public.family_members (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  name       text not null check (length(trim(name)) > 0),
  created_at timestamptz not null default now()
);

-- Two people called "Abba" in one house would make the breakdown unreadable.
-- Case-insensitive, so "abba" cannot slip past it either.
create unique index if not exists family_members_user_name_idx
  on public.family_members (user_id, lower(trim(name)));

-- Who spent it. Nullable on purpose: expenses logged before the family was set
-- up keep working, and `set null` means removing a person leaves their spending
-- in the totals as unattributed rather than deleting real money from history.
alter table public.expenses
  add column if not exists member_id uuid
    references public.family_members (id) on delete set null;

create index if not exists expenses_user_member_idx
  on public.expenses (user_id, member_id);

-- ---------------------------------------------------------------- projects ---
-- One-off undertakings paid for out of savings: building a house, a wedding,
-- a car. Deliberately a separate ledger from `expenses` — nothing here counts
-- towards a monthly total, a category budget, or the savings figure.
create table if not exists public.projects (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  name       text not null check (length(trim(name)) > 0),
  -- What the whole job is expected to cost. Null when no target was set.
  estimate   numeric(14, 2) check (estimate is null or estimate > 0),
  note       text not null default '',
  started_on date not null default current_date,
  created_at timestamptz not null default now()
);

create index if not exists projects_user_started_idx
  on public.projects (user_id, started_on desc);

-- One line of a project's ledger. Either a measured buy (5,000 bricks at
-- Rs 18.50) or a lump sum (a week of mason's wages); `amount` is stored either
-- way, so a total is always a plain sum.
create table if not exists public.project_entries (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  -- Deleting a project takes its entries with it.
  project_id uuid not null references public.projects (id) on delete cascade,
  -- Which part of the job: 'Bricks', 'Cement', 'Mason labour'. Free text, so a
  -- project can name its own stages.
  stage      text not null default '',
  amount     numeric(14, 2) not null check (amount > 0),
  -- Set together or both null: an amount cannot be re-derived from half a pair.
  quantity   numeric(14, 3) check (quantity is null or quantity > 0),
  unit       text not null default '',
  rate       numeric(14, 4) check (rate is null or rate > 0),
  spent_on   date not null,
  note       text not null default '',
  created_at timestamptz not null default now(),
  constraint project_entries_measure_pair
    check ((quantity is null) = (rate is null))
);

create index if not exists project_entries_project_idx
  on public.project_entries (user_id, project_id, spent_on desc);

-- ---------------------------------------------------------------- vehicles ---
-- The household's cars and bikes, and every tuning or service done on them.
-- Another separate ledger: service costs never count towards a monthly total,
-- a category budget, or the savings figure. It is a maintenance logbook.
create table if not exists public.vehicles (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
               references auth.users (id) on delete cascade,
  name       text not null check (length(trim(name)) > 0),
  kind       text not null default 'car' check (kind in ('car', 'bike')),
  plate      text not null default '',
  -- Last reading typed in for the vehicle itself, in km.
  odometer   integer not null default 0 check (odometer >= 0),
  note       text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists vehicles_user_idx
  on public.vehicles (user_id, created_at);

-- One visit to the workshop. The interval is stored on the record, so changing
-- a default later never rewrites when an old service said the next was due.
create table if not exists public.vehicle_services (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid()
                    references auth.users (id) on delete cascade,
  -- Deleting a vehicle takes its service history with it.
  vehicle_id      uuid not null
                    references public.vehicles (id) on delete cascade,
  service         text not null default '',
  serviced_on     date not null,
  odometer        integer not null check (odometer >= 0),
  cost            numeric(14, 2) not null default 0 check (cost >= 0),
  -- Due again after this many km / months. Null when that limit does not
  -- apply; both null means the record is history only.
  interval_km     integer check (interval_km is null or interval_km > 0),
  interval_months integer
                    check (interval_months is null or interval_months > 0),
  workshop        text not null default '',
  note            text not null default '',
  created_at      timestamptz not null default now()
);

create index if not exists vehicle_services_vehicle_idx
  on public.vehicle_services (user_id, vehicle_id, serviced_on desc);

-- --------------------------------------------------------------------- RLS ---
-- Row level security is the only thing separating accounts: the key shipped in
-- the app is public, so every policy pins rows to auth.uid().
alter table public.expenses        enable row level security;
alter table public.budgets         enable row level security;
alter table public.monthly_income  enable row level security;
alter table public.projects        enable row level security;
alter table public.project_entries enable row level security;
alter table public.family_members  enable row level security;
alter table public.vehicles        enable row level security;
alter table public.vehicle_services enable row level security;

drop policy if exists expenses_select_own on public.expenses;
create policy expenses_select_own on public.expenses for select
  to authenticated using (auth.uid() = user_id);

-- An expense can only name a member of the caller's own household. Checking the
-- parent as well as user_id stops a client attaching its spending to someone
-- else's family by sending their member_id.
drop policy if exists expenses_insert_own on public.expenses;
create policy expenses_insert_own on public.expenses for insert
  to authenticated with check (
    auth.uid() = user_id
    and (
      member_id is null
      or exists (
        select 1 from public.family_members m
        where m.id = member_id and m.user_id = auth.uid()
      )
    )
  );

drop policy if exists expenses_update_own on public.expenses;
create policy expenses_update_own on public.expenses for update
  to authenticated using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (
      member_id is null
      or exists (
        select 1 from public.family_members m
        where m.id = member_id and m.user_id = auth.uid()
      )
    )
  );

drop policy if exists expenses_delete_own on public.expenses;
create policy expenses_delete_own on public.expenses for delete
  to authenticated using (auth.uid() = user_id);

drop policy if exists budgets_select_own on public.budgets;
create policy budgets_select_own on public.budgets for select
  to authenticated using (auth.uid() = user_id);

drop policy if exists budgets_insert_own on public.budgets;
create policy budgets_insert_own on public.budgets for insert
  to authenticated with check (auth.uid() = user_id);

drop policy if exists budgets_update_own on public.budgets;
create policy budgets_update_own on public.budgets for update
  to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists budgets_delete_own on public.budgets;
create policy budgets_delete_own on public.budgets for delete
  to authenticated using (auth.uid() = user_id);

drop policy if exists income_select_own on public.monthly_income;
create policy income_select_own on public.monthly_income for select
  to authenticated using (auth.uid() = user_id);

drop policy if exists income_insert_own on public.monthly_income;
create policy income_insert_own on public.monthly_income for insert
  to authenticated with check (auth.uid() = user_id);

drop policy if exists income_update_own on public.monthly_income;
create policy income_update_own on public.monthly_income for update
  to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists income_delete_own on public.monthly_income;
create policy income_delete_own on public.monthly_income for delete
  to authenticated using (auth.uid() = user_id);

drop policy if exists projects_select_own on public.projects;
create policy projects_select_own on public.projects for select
  to authenticated using (auth.uid() = user_id);

drop policy if exists projects_insert_own on public.projects;
create policy projects_insert_own on public.projects for insert
  to authenticated with check (auth.uid() = user_id);

drop policy if exists projects_update_own on public.projects;
create policy projects_update_own on public.projects for update
  to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists projects_delete_own on public.projects;
create policy projects_delete_own on public.projects for delete
  to authenticated using (auth.uid() = user_id);

-- An entry is reachable only through a project the caller owns. Checking the
-- parent as well as user_id stops a client attaching a row to someone else's
-- project by sending their project_id.
drop policy if exists project_entries_select_own on public.project_entries;
create policy project_entries_select_own on public.project_entries for select
  to authenticated using (auth.uid() = user_id);

drop policy if exists project_entries_insert_own on public.project_entries;
create policy project_entries_insert_own on public.project_entries for insert
  to authenticated with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.projects p
      where p.id = project_id and p.user_id = auth.uid()
    )
  );

drop policy if exists project_entries_update_own on public.project_entries;
create policy project_entries_update_own on public.project_entries for update
  to authenticated using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.projects p
      where p.id = project_id and p.user_id = auth.uid()
    )
  );

drop policy if exists project_entries_delete_own on public.project_entries;
create policy project_entries_delete_own on public.project_entries for delete
  to authenticated using (auth.uid() = user_id);

drop policy if exists members_select_own on public.family_members;
create policy members_select_own on public.family_members for select
  to authenticated using (auth.uid() = user_id);

drop policy if exists members_insert_own on public.family_members;
create policy members_insert_own on public.family_members for insert
  to authenticated with check (auth.uid() = user_id);

drop policy if exists members_update_own on public.family_members;
create policy members_update_own on public.family_members for update
  to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists members_delete_own on public.family_members;
create policy members_delete_own on public.family_members for delete
  to authenticated using (auth.uid() = user_id);

drop policy if exists vehicles_select_own on public.vehicles;
create policy vehicles_select_own on public.vehicles for select
  to authenticated using (auth.uid() = user_id);

drop policy if exists vehicles_insert_own on public.vehicles;
create policy vehicles_insert_own on public.vehicles for insert
  to authenticated with check (auth.uid() = user_id);

drop policy if exists vehicles_update_own on public.vehicles;
create policy vehicles_update_own on public.vehicles for update
  to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists vehicles_delete_own on public.vehicles;
create policy vehicles_delete_own on public.vehicles for delete
  to authenticated using (auth.uid() = user_id);

-- A service record is reachable only through a vehicle the caller owns, for the
-- same reason project entries check their project.
drop policy if exists vehicle_services_select_own on public.vehicle_services;
create policy vehicle_services_select_own on public.vehicle_services for select
  to authenticated using (auth.uid() = user_id);

drop policy if exists vehicle_services_insert_own on public.vehicle_services;
create policy vehicle_services_insert_own on public.vehicle_services for insert
  to authenticated with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.vehicles v
      where v.id = vehicle_id and v.user_id = auth.uid()
    )
  );

drop policy if exists vehicle_services_update_own on public.vehicle_services;
create policy vehicle_services_update_own on public.vehicle_services for update
  to authenticated using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.vehicles v
      where v.id = vehicle_id and v.user_id = auth.uid()
    )
  );

drop policy if exists vehicle_services_delete_own on public.vehicle_services;
create policy vehicle_services_delete_own on public.vehicle_services for delete
  to authenticated using (auth.uid() = user_id);

-- Check after running (expects 4 policies per table):
--   select tablename, cmd, policyname from pg_policies
--   where tablename in ('expenses', 'budgets', 'monthly_income',
--                       'projects', 'project_entries', 'family_members',
--                       'vehicles', 'vehicle_services')
--   order by tablename, cmd;
