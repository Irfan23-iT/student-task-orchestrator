CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS public.workspaces (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  invite_code TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.workspace_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member',
  status TEXT NOT NULL DEFAULT 'active',
  invited_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
  display_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT workspace_members_role_chk CHECK (role IN ('owner', 'manager', 'member', 'viewer')),
  CONSTRAINT workspace_members_status_chk CHECK (status IN ('active', 'invited', 'removed')),
  CONSTRAINT workspace_members_workspace_user_uidx UNIQUE (workspace_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.workspace_tasks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  sub_task_id UUID NOT NULL REFERENCES public.sub_tasks(id) ON DELETE CASCADE,
  assignee_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  assigned_by_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT workspace_tasks_status_chk CHECK (status IN ('active', 'completed', 'blocked', 'archived')),
  CONSTRAINT workspace_tasks_workspace_sub_task_uidx UNIQUE (workspace_id, sub_task_id)
);

CREATE TABLE IF NOT EXISTS public.workspace_activity_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  actor_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.completion_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  sub_task_id UUID REFERENCES public.sub_tasks(id) ON DELETE SET NULL,
  workspace_id UUID REFERENCES public.workspaces(id) ON DELETE SET NULL,
  completed_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  event_day DATE GENERATED ALWAYS AS ((completed_at AT TIME ZONE 'UTC')::DATE) STORED,
  source_surface TEXT NOT NULL DEFAULT 'dashboard',
  payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.productivity_daily_stats (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  stat_day DATE NOT NULL,
  completed_count INTEGER NOT NULL DEFAULT 0,
  open_count INTEGER NOT NULL DEFAULT 0,
  completed_minutes INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT productivity_daily_stats_user_day_uidx UNIQUE (user_id, stat_day)
);

CREATE TABLE IF NOT EXISTS public.workspace_productivity_stats (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  workspace_id UUID NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  stat_day DATE NOT NULL,
  completed_count INTEGER NOT NULL DEFAULT 0,
  active_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT workspace_productivity_stats_workspace_day_uidx UNIQUE (workspace_id, stat_day)
);

CREATE TABLE IF NOT EXISTS public.streak_snapshots (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  streak_day DATE NOT NULL,
  streak_count INTEGER NOT NULL DEFAULT 0,
  longest_streak INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT streak_snapshots_user_day_uidx UNIQUE (user_id, streak_day)
);

CREATE TABLE IF NOT EXISTS public.badges (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  badge_key TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  description TEXT NOT NULL,
  tone TEXT NOT NULL DEFAULT 'secondary',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_badges (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  badge_id UUID NOT NULL REFERENCES public.badges(id) ON DELETE CASCADE,
  awarded_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  CONSTRAINT user_badges_user_badge_uidx UNIQUE (user_id, badge_id)
);

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  inbox_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  email_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  reminder_lead_minutes INTEGER NOT NULL DEFAULT 30,
  quiet_hours_start TIME NOT NULL DEFAULT TIME '22:00',
  quiet_hours_end TIME NOT NULL DEFAULT TIME '07:00',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.web_push_subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL UNIQUE,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.reminder_jobs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  sub_task_id UUID REFERENCES public.sub_tasks(id) ON DELETE SET NULL,
  workspace_id UUID REFERENCES public.workspaces(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  reminder_at TIMESTAMP WITH TIME ZONE NOT NULL,
  channel TEXT NOT NULL DEFAULT 'inbox',
  status TEXT NOT NULL DEFAULT 'scheduled',
  payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT reminder_jobs_channel_chk CHECK (channel IN ('inbox', 'email', 'push')),
  CONSTRAINT reminder_jobs_status_chk CHECK (status IN ('scheduled', 'sent', 'dismissed', 'cancelled', 'failed'))
);

CREATE TABLE IF NOT EXISTS public.reminder_deliveries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reminder_job_id UUID NOT NULL REFERENCES public.reminder_jobs(id) ON DELETE CASCADE,
  channel TEXT NOT NULL DEFAULT 'inbox',
  delivery_state TEXT NOT NULL DEFAULT 'pending',
  delivered_at TIMESTAMP WITH TIME ZONE,
  read_at TIMESTAMP WITH TIME ZONE,
  error_message TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT reminder_deliveries_channel_chk CHECK (channel IN ('inbox', 'email', 'push')),
  CONSTRAINT reminder_deliveries_state_chk CHECK (delivery_state IN ('pending', 'sent', 'read', 'failed'))
);

CREATE INDEX IF NOT EXISTS workspaces_owner_updated_idx ON public.workspaces(owner_user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS workspace_members_user_idx ON public.workspace_members(user_id, workspace_id);
CREATE INDEX IF NOT EXISTS workspace_tasks_workspace_idx ON public.workspace_tasks(workspace_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS workspace_activity_events_workspace_idx ON public.workspace_activity_events(workspace_id, created_at DESC);
CREATE INDEX IF NOT EXISTS completion_events_user_day_idx ON public.completion_events(user_id, completed_at DESC);
CREATE INDEX IF NOT EXISTS user_badges_user_awarded_idx ON public.user_badges(user_id, awarded_at DESC);
CREATE INDEX IF NOT EXISTS reminder_jobs_user_reminder_idx ON public.reminder_jobs(user_id, reminder_at ASC);
CREATE INDEX IF NOT EXISTS reminder_deliveries_user_created_idx ON public.reminder_deliveries(user_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.is_workspace_member(
  p_workspace_id UUID,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.workspace_members AS member
    WHERE member.workspace_id = p_workspace_id
      AND member.user_id = COALESCE(p_user_id, auth.uid())
      AND member.status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_workspace_manager(
  p_workspace_id UUID,
  p_user_id UUID DEFAULT auth.uid()
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.workspace_members AS member
    WHERE member.workspace_id = p_workspace_id
      AND member.user_id = COALESCE(p_user_id, auth.uid())
      AND member.status = 'active'
      AND member.role IN ('owner', 'manager')
  );
$$;

INSERT INTO public.badges (badge_key, label, description, tone)
VALUES
  ('streak-3', 'Three-Day Pulse', 'Completed work three days in a row.', 'secondary'),
  ('streak-7', 'Seven-Day Flame', 'Held a seven-day completion streak.', 'success'),
  ('tasks-10', 'Ten Tasks Down', 'Closed ten tasks.', 'default'),
  ('tasks-25', 'Quarter-Century', 'Closed twenty-five tasks.', 'outline')
ON CONFLICT (badge_key) DO UPDATE
SET label = EXCLUDED.label,
    description = EXCLUDED.description,
    tone = EXCLUDED.tone;

ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_activity_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.completion_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.productivity_daily_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workspace_productivity_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.streak_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_badges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.web_push_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reminder_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reminder_deliveries ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspaces' AND policyname = 'Workspace members can view workspaces') THEN
    CREATE POLICY "Workspace members can view workspaces" ON public.workspaces FOR SELECT TO authenticated USING (owner_user_id = auth.uid() OR public.is_workspace_member(id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspaces' AND policyname = 'Owners can create workspaces') THEN
    CREATE POLICY "Owners can create workspaces" ON public.workspaces FOR INSERT TO authenticated WITH CHECK (owner_user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspaces' AND policyname = 'Managers can update workspaces') THEN
    CREATE POLICY "Managers can update workspaces" ON public.workspaces FOR UPDATE TO authenticated USING (owner_user_id = auth.uid() OR public.is_workspace_manager(id)) WITH CHECK (owner_user_id = auth.uid() OR public.is_workspace_manager(id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspace_members' AND policyname = 'Workspace members can view members') THEN
    CREATE POLICY "Workspace members can view members" ON public.workspace_members FOR SELECT TO authenticated USING (public.is_workspace_member(workspace_id) OR EXISTS (SELECT 1 FROM public.workspaces AS workspace WHERE workspace.id = workspace_id AND workspace.owner_user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspace_members' AND policyname = 'Managers can manage members') THEN
    CREATE POLICY "Managers can manage members" ON public.workspace_members FOR ALL TO authenticated USING (public.is_workspace_manager(workspace_id) OR EXISTS (SELECT 1 FROM public.workspaces AS workspace WHERE workspace.id = workspace_id AND workspace.owner_user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM public.workspaces AS workspace WHERE workspace.id = workspace_id AND workspace.owner_user_id = auth.uid()) OR public.is_workspace_manager(workspace_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspace_tasks' AND policyname = 'Workspace members can view assignments') THEN
    CREATE POLICY "Workspace members can view assignments" ON public.workspace_tasks FOR SELECT TO authenticated USING (public.is_workspace_member(workspace_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspace_tasks' AND policyname = 'Managers can manage assignments') THEN
    CREATE POLICY "Managers can manage assignments" ON public.workspace_tasks FOR ALL TO authenticated USING (public.is_workspace_manager(workspace_id)) WITH CHECK (public.is_workspace_manager(workspace_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspace_activity_events' AND policyname = 'Workspace members can view activity') THEN
    CREATE POLICY "Workspace members can view activity" ON public.workspace_activity_events FOR SELECT TO authenticated USING (public.is_workspace_member(workspace_id));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspace_activity_events' AND policyname = 'Workspace members can write activity') THEN
    CREATE POLICY "Workspace members can write activity" ON public.workspace_activity_events FOR INSERT TO authenticated WITH CHECK (public.is_workspace_member(workspace_id) AND actor_user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'badges' AND policyname = 'Authenticated users can view badges') THEN
    CREATE POLICY "Authenticated users can view badges" ON public.badges FOR SELECT TO authenticated USING (TRUE);
  END IF;
END $$;

DO $$
DECLARE
  protected_table TEXT;
BEGIN
  FOREACH protected_table IN ARRAY ARRAY[
    'completion_events',
    'productivity_daily_stats',
    'streak_snapshots',
    'user_badges',
    'notification_preferences',
    'web_push_subscriptions',
    'reminder_jobs',
    'reminder_deliveries'
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

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'workspace_productivity_stats'
      AND policyname = 'Workspace members can view workspace productivity stats'
  ) THEN
    CREATE POLICY "Workspace members can view workspace productivity stats"
      ON public.workspace_productivity_stats
      FOR SELECT
      TO authenticated
      USING (public.is_workspace_member(workspace_id));
  END IF;
END $$;

DROP TRIGGER IF EXISTS set_workspaces_updated_at ON public.workspaces;
CREATE TRIGGER set_workspaces_updated_at BEFORE UPDATE ON public.workspaces FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_workspace_members_updated_at ON public.workspace_members;
CREATE TRIGGER set_workspace_members_updated_at BEFORE UPDATE ON public.workspace_members FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_workspace_tasks_updated_at ON public.workspace_tasks;
CREATE TRIGGER set_workspace_tasks_updated_at BEFORE UPDATE ON public.workspace_tasks FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_productivity_daily_stats_updated_at ON public.productivity_daily_stats;
CREATE TRIGGER set_productivity_daily_stats_updated_at BEFORE UPDATE ON public.productivity_daily_stats FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_workspace_productivity_stats_updated_at ON public.workspace_productivity_stats;
CREATE TRIGGER set_workspace_productivity_stats_updated_at BEFORE UPDATE ON public.workspace_productivity_stats FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_streak_snapshots_updated_at ON public.streak_snapshots;
CREATE TRIGGER set_streak_snapshots_updated_at BEFORE UPDATE ON public.streak_snapshots FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_notification_preferences_updated_at ON public.notification_preferences;
CREATE TRIGGER set_notification_preferences_updated_at BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_web_push_subscriptions_updated_at ON public.web_push_subscriptions;
CREATE TRIGGER set_web_push_subscriptions_updated_at BEFORE UPDATE ON public.web_push_subscriptions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_reminder_jobs_updated_at ON public.reminder_jobs;
CREATE TRIGGER set_reminder_jobs_updated_at BEFORE UPDATE ON public.reminder_jobs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
DROP TRIGGER IF EXISTS set_reminder_deliveries_updated_at ON public.reminder_deliveries;
CREATE TRIGGER set_reminder_deliveries_updated_at BEFORE UPDATE ON public.reminder_deliveries FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
