UPDATE public.workspaces
SET invite_code = UPPER(SUBSTRING(REPLACE(uuid_generate_v4()::TEXT, '-', '') FROM 1 FOR 8))
WHERE invite_code IS NULL OR BTRIM(invite_code) = '';

CREATE UNIQUE INDEX IF NOT EXISTS workspaces_invite_code_uidx
  ON public.workspaces ((LOWER(invite_code)))
  WHERE invite_code IS NOT NULL AND BTRIM(invite_code) <> '';
