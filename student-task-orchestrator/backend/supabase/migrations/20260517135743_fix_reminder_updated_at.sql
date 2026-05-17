alter table public.reminder_jobs
  add column if not exists updated_at timestamp with time zone default now();

update public.reminder_jobs
set updated_at = now()
where updated_at is null;
