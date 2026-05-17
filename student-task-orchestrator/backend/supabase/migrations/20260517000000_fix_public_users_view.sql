drop view if exists public.users;

create view public.users as
select
  id,
  email,
  raw_user_meta_data,
  raw_user_meta_data->>'full_name' as full_name,
  created_at
from auth.users;

grant select on public.users to anon, authenticated, service_role;
