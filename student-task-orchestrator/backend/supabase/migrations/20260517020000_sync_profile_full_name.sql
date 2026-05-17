alter table public.user_profiles
  add column if not exists full_name text;

update public.user_profiles profile
set full_name = auth_user.raw_user_meta_data->>'full_name'
from auth.users auth_user
where profile.user_id = auth_user.id
  and nullif(trim(coalesce(profile.full_name, '')), '') is null
  and nullif(trim(coalesce(auth_user.raw_user_meta_data->>'full_name', '')), '') is not null;

drop view if exists public.users;

create view public.users as
select
  auth_user.id,
  auth_user.email,
  auth_user.raw_user_meta_data,
  coalesce(profile.full_name, auth_user.raw_user_meta_data->>'full_name') as full_name,
  auth_user.created_at
from auth.users auth_user
left join public.user_profiles profile
  on profile.user_id = auth_user.id;

grant select on public.users to anon, authenticated, service_role;
