-- Shipped sync schema.
-- Paste this whole file into Supabase's SQL Editor (left sidebar) and click Run, once.

create table if not exists goals (
  id uuid primary key,
  sync_group text not null,
  title text not null,
  deadline timestamptz not null,
  original_deadline timestamptz not null,
  created_at timestamptz not null,
  capacity text not null,
  check_in_hour int not null,
  recut_count int not null default 0,
  is_archived boolean not null default false,
  completed_at timestamptz,
  rest_days jsonb not null default '[]',
  plan_snapshot jsonb,
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);

create table if not exists daily_tasks (
  id uuid primary key,
  sync_group text not null,
  goal_id uuid not null references goals(id) on delete cascade,
  date timestamptz not null,
  title text not null,
  is_done boolean not null default false,
  task_order int not null default 0,
  updated_at timestamptz not null default now(),
  deleted boolean not null default false
);

create index if not exists goals_sync_group_idx on goals(sync_group, updated_at);
create index if not exists tasks_sync_group_idx on daily_tasks(sync_group, updated_at);
create index if not exists tasks_goal_idx on daily_tasks(goal_id);

alter table goals enable row level security;
alter table daily_tasks enable row level security;

-- IMPORTANT — read this.
-- This policy is permissive: anyone holding the anon key can read/write any row. There is
-- no real per-user auth wired up yet (that would mean mapping the app's existing Sign in
-- with Apple / Google / email into Supabase Auth and switching this policy to check
-- auth.uid()). For a personal app used by one person across their own two devices, with the
-- key embedded only in a build you compile yourself, this is a reasonable tradeoff — but
-- it is not the same thing as real security, and don't reuse this schema for anything
-- multi-user without tightening it first.
create policy "shipped_personal_use" on goals for all using (true) with check (true);
create policy "shipped_personal_use" on daily_tasks for all using (true) with check (true);
