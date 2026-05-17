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
  updated_at timestamptz not null default now(),
  constraint orchestration_runs_status_chk check (
    status in (
      'QUEUED',
      'PROCESSING',
      'COMPLETED',
      'COMPLETED_WITH_WARNINGS',
      'FAILED',
      'FAILED_TIMEOUT',
      'CANCELLED'
    )
  ),
  constraint orchestration_runs_attempt_count_chk check (attempt_count >= 1)
);

create unique index if not exists orchestration_runs_user_idempotency_uidx
  on public.orchestration_runs(user_id, idempotency_key);

create index if not exists orchestration_runs_user_updated_idx
  on public.orchestration_runs(user_id, updated_at desc);

create index if not exists orchestration_runs_status_lease_idx
  on public.orchestration_runs(status, lease_expires_at);

alter table public.orchestration_runs enable row level security;

drop policy if exists "Users can manage their own orchestration runs"
  on public.orchestration_runs;

create policy "Users can manage their own orchestration runs"
  on public.orchestration_runs
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop trigger if exists set_orchestration_runs_updated_at
  on public.orchestration_runs;

create trigger set_orchestration_runs_updated_at
before update on public.orchestration_runs
for each row
execute function public.set_updated_at();
