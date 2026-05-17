CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS public.calendar_connections (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL DEFAULT 'google',
  email TEXT,
  access_token TEXT,
  refresh_token TEXT NOT NULL,
  id_token TEXT,
  granted_scopes TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  token_expires_at TIMESTAMP WITH TIME ZONE,
  sync_status TEXT NOT NULL DEFAULT 'pending',
  last_sync_at TIMESTAMP WITH TIME ZONE,
  next_sync_at TIMESTAMP WITH TIME ZONE,
  last_error TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT calendar_connections_provider_chk CHECK (provider IN ('google')),
  CONSTRAINT calendar_connections_sync_status_chk CHECK (sync_status IN ('pending', 'healthy', 'error', 'disconnected')),
  CONSTRAINT calendar_connections_user_provider_uidx UNIQUE (user_id, provider)
);

CREATE TABLE IF NOT EXISTS public.calendar_calendars (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  connection_id UUID NOT NULL REFERENCES public.calendar_connections(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  external_calendar_id TEXT NOT NULL,
  summary TEXT NOT NULL,
  primary_calendar BOOLEAN NOT NULL DEFAULT FALSE,
  selected BOOLEAN NOT NULL DEFAULT TRUE,
  access_role TEXT NOT NULL DEFAULT 'reader',
  background_color TEXT,
  foreground_color TEXT,
  time_zone TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT calendar_calendars_user_external_uidx UNIQUE (user_id, external_calendar_id)
);

CREATE TABLE IF NOT EXISTS public.calendar_busy_intervals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  connection_id UUID NOT NULL REFERENCES public.calendar_connections(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  external_calendar_id TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'google',
  starts_at TIMESTAMP WITH TIME ZONE NOT NULL,
  ends_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT calendar_busy_intervals_window_chk CHECK (starts_at < ends_at)
);

CREATE TABLE IF NOT EXISTS public.managed_schedule_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  connection_id UUID NOT NULL REFERENCES public.calendar_connections(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  sub_task_id UUID NOT NULL REFERENCES public.sub_tasks(id) ON DELETE CASCADE,
  external_calendar_id TEXT NOT NULL,
  external_event_id TEXT,
  starts_at TIMESTAMP WITH TIME ZONE,
  ends_at TIMESTAMP WITH TIME ZONE,
  status TEXT NOT NULL DEFAULT 'synced',
  last_synced_at TIMESTAMP WITH TIME ZONE,
  last_error TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  payload_hash TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT managed_schedule_events_status_chk CHECK (status IN ('synced', 'pending', 'error', 'deleted')),
  CONSTRAINT managed_schedule_events_user_sub_task_uidx UNIQUE (user_id, sub_task_id)
);

CREATE INDEX IF NOT EXISTS calendar_connections_user_next_sync_idx
  ON public.calendar_connections(user_id, next_sync_at);
CREATE INDEX IF NOT EXISTS calendar_busy_intervals_user_starts_idx
  ON public.calendar_busy_intervals(user_id, starts_at);
CREATE INDEX IF NOT EXISTS managed_schedule_events_user_starts_idx
  ON public.managed_schedule_events(user_id, starts_at);

ALTER TABLE public.calendar_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.calendar_calendars ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.calendar_busy_intervals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.managed_schedule_events ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  protected_table TEXT;
BEGIN
  FOREACH protected_table IN ARRAY ARRAY[
    'calendar_connections',
    'calendar_calendars',
    'calendar_busy_intervals',
    'managed_schedule_events'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = protected_table
        AND policyname = protected_table || '_self_manage'
    ) THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid())',
        protected_table || '_self_manage',
        protected_table
      );
    END IF;
  END LOOP;
END $$;

DROP TRIGGER IF EXISTS set_calendar_connections_updated_at ON public.calendar_connections;
CREATE TRIGGER set_calendar_connections_updated_at
BEFORE UPDATE ON public.calendar_connections
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_calendar_calendars_updated_at ON public.calendar_calendars;
CREATE TRIGGER set_calendar_calendars_updated_at
BEFORE UPDATE ON public.calendar_calendars
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_calendar_busy_intervals_updated_at ON public.calendar_busy_intervals;
CREATE TRIGGER set_calendar_busy_intervals_updated_at
BEFORE UPDATE ON public.calendar_busy_intervals
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_managed_schedule_events_updated_at ON public.managed_schedule_events;
CREATE TRIGGER set_managed_schedule_events_updated_at
BEFORE UPDATE ON public.managed_schedule_events
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
