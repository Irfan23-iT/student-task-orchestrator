create extension if not exists pgcrypto;

create table if not exists public.focus_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  duration_minutes integer not null,
  xp integer not null default 0,
  completed_at timestamptz not null default now(),
  session_day date generated always as ((completed_at at time zone 'UTC')::date) stored,
  created_at timestamptz not null default now(),
  constraint focus_sessions_duration_chk check (duration_minutes > 0 and duration_minutes <= 1440),
  constraint focus_sessions_xp_chk check (xp >= 0)
);

create index if not exists focus_sessions_user_completed_idx
  on public.focus_sessions(user_id, completed_at desc);

alter table public.focus_sessions enable row level security;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'focus_sessions'
      and policyname = 'Users can view their own focus sessions'
  ) then
    create policy "Users can view their own focus sessions"
      on public.focus_sessions
      for select
      to authenticated
      using (user_id = auth.uid());
  end if;
end $$;

create or replace function public.complete_focus_session(
  p_user_id uuid,
  p_duration_minutes integer,
  p_xp integer default 0,
  p_completed_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.focus_sessions%rowtype;
  v_stat_day date := (p_completed_at at time zone 'UTC')::date;
  v_streak_count integer := 0;
  v_longest_streak integer := 0;
  v_cursor date := v_stat_day;
  v_previous_day date;
  v_day date;
  v_running_streak integer := 0;
begin
  if p_user_id is null then
    raise exception 'User id is required.';
  end if;

  if auth.uid() is not null and p_user_id <> auth.uid() then
    raise exception 'Cannot complete focus session for another user.';
  end if;

  if p_duration_minutes is null or p_duration_minutes <= 0 or p_duration_minutes > 1440 then
    raise exception 'duration_minutes must be between 1 and 1440.';
  end if;

  insert into public.focus_sessions (
    user_id,
    duration_minutes,
    xp,
    completed_at
  )
  values (
    p_user_id,
    p_duration_minutes,
    greatest(coalesce(p_xp, 0), 0),
    coalesce(p_completed_at, now())
  )
  returning * into v_session;

  insert into public.completion_events (
    user_id,
    completed_at,
    source_surface,
    payload
  )
  values (
    p_user_id,
    v_session.completed_at,
    'focus_timer',
    jsonb_build_object(
      'focus_session_id', v_session.id,
      'duration_minutes', v_session.duration_minutes,
      'xp', v_session.xp
    )
  );

  insert into public.productivity_daily_stats (
    user_id,
    stat_day,
    completed_count,
    open_count,
    completed_minutes
  )
  values (
    p_user_id,
    v_stat_day,
    1,
    0,
    v_session.duration_minutes
  )
  on conflict (user_id, stat_day)
  do update set
    completed_count = public.productivity_daily_stats.completed_count + 1,
    completed_minutes = public.productivity_daily_stats.completed_minutes + excluded.completed_minutes,
    updated_at = now();

  while exists (
    select 1
    from public.completion_events
    where user_id = p_user_id
      and event_day = v_cursor
  ) loop
    v_streak_count := v_streak_count + 1;
    v_cursor := v_cursor - 1;
  end loop;

  for v_day in
    select distinct event_day
    from public.completion_events
    where user_id = p_user_id
    order by event_day
  loop
    if v_previous_day is null or v_day = v_previous_day + 1 then
      v_running_streak := v_running_streak + 1;
    else
      v_running_streak := 1;
    end if;

    v_previous_day := v_day;
    v_longest_streak := greatest(v_longest_streak, v_running_streak);
  end loop;

  insert into public.streak_snapshots (
    user_id,
    streak_day,
    streak_count,
    longest_streak
  )
  values (
    p_user_id,
    v_stat_day,
    v_streak_count,
    v_longest_streak
  )
  on conflict (user_id, streak_day)
  do update set
    streak_count = excluded.streak_count,
    longest_streak = greatest(public.streak_snapshots.longest_streak, excluded.longest_streak),
    updated_at = now();

  return jsonb_build_object(
    'sessionId', v_session.id,
    'durationMinutes', v_session.duration_minutes,
    'xp', v_session.xp,
    'completedAt', v_session.completed_at,
    'streakCount', v_streak_count,
    'longestStreak', v_longest_streak
  );
end;
$$;
