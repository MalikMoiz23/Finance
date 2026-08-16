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

-- --------------------------------------------------------------------- RLS ---
-- Row level security is the only thing separating accounts: the key shipped in
-- the app is public, so every policy pins rows to auth.uid().
alter table public.expenses        enable row level security;
alter table public.budgets         enable row level security;
alter table public.monthly_income  enable row level security;
alter table public.projects        enable row level security;
alter table public.project_entries enable row level security;

drop policy if exists expenses_select_own on public.expenses;
create policy expenses_select_own on public.expenses for select
  to authenticated using (auth.uid() = user_id);

drop policy if exists expenses_insert_own on public.expenses;
create policy expenses_insert_own on public.expenses for insert
  to authenticated with check (auth.uid() = user_id);

drop policy if exists expenses_update_own on public.expenses;
create policy expenses_update_own on public.expenses for update
  to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

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

-- Check after running (expects 4 policies per table):
--   select tablename, cmd, policyname from pg_policies
--   where tablename in ('expenses', 'budgets', 'monthly_income',
--                       'projects', 'project_entries')
--   order by tablename, cmd;
