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

create index if not exists web_push_subscriptions_user_updated_idx
  on public.web_push_subscriptions(user_id, updated_at desc);

alter table public.web_push_subscriptions enable row level security;

drop policy if exists "Users can manage their own web push subscriptions"
  on public.web_push_subscriptions;

create policy "Users can manage their own web push subscriptions"
  on public.web_push_subscriptions
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop trigger if exists set_web_push_subscriptions_updated_at
  on public.web_push_subscriptions;

create trigger set_web_push_subscriptions_updated_at
before update on public.web_push_subscriptions
for each row
execute function public.set_updated_at();
