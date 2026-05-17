create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.completion_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  sub_task_id uuid,
  workspace_id uuid,
  completed_at timestamptz not null default now(),
  event_day date generated always as ((completed_at at time zone 'UTC')::date) stored,
  source_surface text not null default 'dashboard',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.productivity_daily_stats (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  stat_day date not null,
  completed_count integer not null default 0,
  open_count integer not null default 0,
  completed_minutes integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint productivity_daily_stats_user_day_uidx unique (user_id, stat_day)
);

create table if not exists public.streak_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  streak_day date not null,
  streak_count integer not null default 0,
  longest_streak integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint streak_snapshots_user_day_uidx unique (user_id, streak_day)
);

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  inbox_enabled boolean not null default true,
  email_enabled boolean not null default false,
  reminder_lead_minutes integer not null default 30,
  quiet_hours_start time not null default time '22:00',
  quiet_hours_end time not null default time '07:00',
  time_zone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_preferences_reminder_lead_chk check (
    reminder_lead_minutes between 5 and 10080
  )
);

create table if not exists public.reminder_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  sub_task_id uuid,
  workspace_id uuid,
  title text not null,
  reminder_at timestamptz not null,
  channel text not null default 'inbox',
  status text not null default 'scheduled',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint reminder_jobs_channel_chk check (channel in ('inbox', 'email', 'push')),
  constraint reminder_jobs_status_chk check (
    status in ('scheduled', 'sent', 'dismissed', 'cancelled', 'failed')
  )
);

create table if not exists public.reminder_deliveries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reminder_job_id uuid references public.reminder_jobs(id) on delete cascade,
  channel text not null default 'inbox',
  delivery_state text not null default 'pending',
  delivered_at timestamptz,
  read_at timestamptz,
  error_message text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.reminder_deliveries
  add column if not exists reminder_job_id uuid references public.reminder_jobs(id) on delete cascade,
  add column if not exists channel text not null default 'inbox',
  add column if not exists delivery_state text not null default 'pending',
  add column if not exists read_at timestamptz,
  add column if not exists payload jsonb not null default '{}'::jsonb,
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'reminder_deliveries'
      and column_name = 'job_id'
  ) then
    execute 'update public.reminder_deliveries set reminder_job_id = job_id where reminder_job_id is null';
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'reminder_deliveries_channel_chk'
      and conrelid = 'public.reminder_deliveries'::regclass
  ) then
    alter table public.reminder_deliveries
      add constraint reminder_deliveries_channel_chk
      check (channel in ('inbox', 'email', 'push'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'reminder_deliveries_state_chk'
      and conrelid = 'public.reminder_deliveries'::regclass
  ) then
    alter table public.reminder_deliveries
      add constraint reminder_deliveries_state_chk
      check (delivery_state in ('pending', 'sent', 'read', 'failed'));
  end if;
end $$;

create table if not exists public.badges (
  id uuid primary key default gen_random_uuid(),
  badge_key text not null unique,
  label text not null,
  description text not null,
  tone text not null default 'secondary',
  created_at timestamptz not null default now()
);

create table if not exists public.user_badges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_id uuid not null references public.badges(id) on delete cascade,
  awarded_at timestamptz not null default now(),
  payload jsonb not null default '{}'::jsonb,
  constraint user_badges_user_badge_uidx unique (user_id, badge_id)
);

create table if not exists public.web_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orchestration_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  status text not null,
  attempt_count integer not null default 1,
  idempotency_key text not null,
  payload_hash text not null,
  request_id text,
  source_surface text not null default 'dashboard',
  payload jsonb not null default '{}'::jsonb,
  result_payload jsonb not null default '{}'::jsonb,
  warning_summary jsonb not null default '{}'::jsonb,
  error_message text,
  queued_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  lease_owner text,
  lease_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.badges (badge_key, label, description, tone)
values
  ('streak-3', 'Three-Day Pulse', 'Completed work three days in a row.', 'secondary'),
  ('streak-7', 'Seven-Day Flame', 'Held a seven-day completion streak.', 'success'),
  ('tasks-10', 'Ten Tasks Down', 'Closed ten tasks.', 'default'),
  ('tasks-25', 'Quarter-Century', 'Closed twenty-five tasks.', 'outline')
on conflict (badge_key) do update
set label = excluded.label,
    description = excluded.description,
    tone = excluded.tone;

create index if not exists completion_events_user_day_idx
  on public.completion_events(user_id, completed_at desc);

create unique index if not exists completion_events_user_task_uidx
  on public.completion_events(user_id, sub_task_id)
  where sub_task_id is not null;

create index if not exists productivity_daily_stats_user_day_idx
  on public.productivity_daily_stats(user_id, stat_day desc);

create index if not exists streak_snapshots_user_day_idx
  on public.streak_snapshots(user_id, streak_day desc);

create index if not exists reminder_jobs_user_reminder_idx
  on public.reminder_jobs(user_id, reminder_at asc);

create index if not exists reminder_deliveries_user_created_idx
  on public.reminder_deliveries(user_id, created_at desc);

create unique index if not exists reminder_deliveries_job_channel_uidx
  on public.reminder_deliveries(reminder_job_id, channel)
  where reminder_job_id is not null;

create index if not exists user_badges_user_awarded_idx
  on public.user_badges(user_id, awarded_at desc);

create index if not exists web_push_subscriptions_user_updated_idx
  on public.web_push_subscriptions(user_id, updated_at desc);

create unique index if not exists orchestration_runs_user_idempotency_uidx
  on public.orchestration_runs(user_id, idempotency_key);

create index if not exists orchestration_runs_user_updated_idx
  on public.orchestration_runs(user_id, updated_at desc);

create index if not exists orchestration_runs_status_lease_idx
  on public.orchestration_runs(status, lease_expires_at);

alter table public.completion_events enable row level security;
alter table public.productivity_daily_stats enable row level security;
alter table public.streak_snapshots enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.reminder_jobs enable row level security;
alter table public.reminder_deliveries enable row level security;
alter table public.badges enable row level security;
alter table public.user_badges enable row level security;
alter table public.web_push_subscriptions enable row level security;
alter table public.orchestration_runs enable row level security;

drop policy if exists "Authenticated users can view badges" on public.badges;
create policy "Authenticated users can view badges"
  on public.badges for select to authenticated using (true);

do $$
declare
  protected_table text;
begin
  foreach protected_table in array array[
    'completion_events',
    'productivity_daily_stats',
    'streak_snapshots',
    'notification_preferences',
    'reminder_jobs',
    'reminder_deliveries',
    'user_badges',
    'web_push_subscriptions',
    'orchestration_runs'
  ]
  loop
    execute format('drop policy if exists %I on public.%I', protected_table || '_self_manage', protected_table);
    execute format(
      'create policy %I on public.%I for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id)',
      protected_table || '_self_manage',
      protected_table
    );
  end loop;
end $$;

drop trigger if exists set_productivity_daily_stats_updated_at on public.productivity_daily_stats;
create trigger set_productivity_daily_stats_updated_at
before update on public.productivity_daily_stats
for each row execute function public.set_updated_at();

drop trigger if exists set_streak_snapshots_updated_at on public.streak_snapshots;
create trigger set_streak_snapshots_updated_at
before update on public.streak_snapshots
for each row execute function public.set_updated_at();

drop trigger if exists set_notification_preferences_updated_at on public.notification_preferences;
create trigger set_notification_preferences_updated_at
before update on public.notification_preferences
for each row execute function public.set_updated_at();

drop trigger if exists set_reminder_jobs_updated_at on public.reminder_jobs;
create trigger set_reminder_jobs_updated_at
before update on public.reminder_jobs
for each row execute function public.set_updated_at();

drop trigger if exists set_reminder_deliveries_updated_at on public.reminder_deliveries;
create trigger set_reminder_deliveries_updated_at
before update on public.reminder_deliveries
for each row execute function public.set_updated_at();

drop trigger if exists set_web_push_subscriptions_updated_at on public.web_push_subscriptions;
create trigger set_web_push_subscriptions_updated_at
before update on public.web_push_subscriptions
for each row execute function public.set_updated_at();

drop trigger if exists set_orchestration_runs_updated_at on public.orchestration_runs;
create trigger set_orchestration_runs_updated_at
before update on public.orchestration_runs
for each row execute function public.set_updated_at();
