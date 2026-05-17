create extension if not exists pgcrypto;

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

create index if not exists user_badges_user_awarded_idx
  on public.user_badges(user_id, awarded_at desc);

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

alter table public.badges enable row level security;
alter table public.user_badges enable row level security;

drop policy if exists "Authenticated users can view badges"
  on public.badges;

create policy "Authenticated users can view badges"
  on public.badges
  for select
  to authenticated
  using (true);

drop policy if exists "Users can manage their own badges"
  on public.user_badges;

create policy "Users can manage their own badges"
  on public.user_badges
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
