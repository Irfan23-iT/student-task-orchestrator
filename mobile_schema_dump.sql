-- Supabase schema dump
-- Generated from project catalog
-- Scope: public schema tables, indexes, RLS policies, foreign keys, triggers, table-referencing functions, enum types, storage buckets, edge function references

-- ============================================================
-- ENUM TYPE: auth.aal_level
-- ============================================================
CREATE TYPE auth.aal_level AS ENUM ('aal1', 'aal2', 'aal3');

-- ============================================================
-- ENUM TYPE: auth.code_challenge_method
-- ============================================================
CREATE TYPE auth.code_challenge_method AS ENUM ('s256', 'plain');

-- ============================================================
-- ENUM TYPE: auth.factor_status
-- ============================================================
CREATE TYPE auth.factor_status AS ENUM ('unverified', 'verified');

-- ============================================================
-- ENUM TYPE: auth.factor_type
-- ============================================================
CREATE TYPE auth.factor_type AS ENUM ('totp', 'webauthn', 'phone');

-- ============================================================
-- ENUM TYPE: auth.oauth_authorization_status
-- ============================================================
CREATE TYPE auth.oauth_authorization_status AS ENUM ('pending', 'approved', 'denied', 'expired');

-- ============================================================
-- ENUM TYPE: auth.oauth_client_type
-- ============================================================
CREATE TYPE auth.oauth_client_type AS ENUM ('public', 'confidential');

-- ============================================================
-- ENUM TYPE: auth.oauth_registration_type
-- ============================================================
CREATE TYPE auth.oauth_registration_type AS ENUM ('dynamic', 'manual');

-- ============================================================
-- ENUM TYPE: auth.oauth_response_type
-- ============================================================
CREATE TYPE auth.oauth_response_type AS ENUM ('code');

-- ============================================================
-- ENUM TYPE: auth.one_time_token_type
-- ============================================================
CREATE TYPE auth.one_time_token_type AS ENUM ('confirmation_token', 'reauthentication_token', 'recovery_token', 'email_change_token_new', 'email_change_token_current', 'phone_change_token');

-- ============================================================
-- ENUM TYPE: realtime.action
-- ============================================================
CREATE TYPE realtime.action AS ENUM ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'ERROR');

-- ============================================================
-- ENUM TYPE: realtime.equality_op
-- ============================================================
CREATE TYPE realtime.equality_op AS ENUM ('eq', 'neq', 'lt', 'lte', 'gt', 'gte', 'in');

-- ============================================================
-- ENUM TYPE: storage.buckettype
-- ============================================================
CREATE TYPE storage.buckettype AS ENUM ('STANDARD', 'ANALYTICS', 'VECTOR');

-- ============================================================
-- TABLE: public.badges
-- ============================================================
CREATE TABLE public.badges (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    badge_key text NOT NULL,
    label text NOT NULL,
    description text NOT NULL,
    tone text DEFAULT 'secondary'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT badges_badge_key_key UNIQUE (badge_key),
    CONSTRAINT badges_pkey PRIMARY KEY (id)
);
ALTER TABLE public.badges ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.calendar_busy_intervals
-- ============================================================
CREATE TABLE public.calendar_busy_intervals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    source text NOT NULL,
    external_event_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    connection_id uuid,
    external_calendar_id text,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    CONSTRAINT calendar_busy_intervals_pkey PRIMARY KEY (id),
    CONSTRAINT calendar_busy_intervals_time_check CHECK (ends_at > starts_at),
    CONSTRAINT calendar_busy_intervals_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.calendar_busy_intervals ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.calendar_calendars
-- ============================================================
CREATE TABLE public.calendar_calendars (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    provider text,
    provider_calendar_id text,
    summary text,
    description text,
    color text,
    time_zone text,
    access_role text,
    sync_token text,
    is_primary boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()),
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()),
    connection_id uuid,
    background_color text,
    foreground_color text,
    color_id text,
    external_calendar_id text,
    primary_calendar boolean DEFAULT false,
    selected boolean DEFAULT true,
    hidden boolean DEFAULT false,
    CONSTRAINT calendar_calendars_pkey PRIMARY KEY (id),
    CONSTRAINT unique_user_calendar UNIQUE (user_id, provider_calendar_id)
);
-- Row Level Security is disabled on public.calendar_calendars;

-- ============================================================
-- TABLE: public.calendar_connections
-- ============================================================
CREATE TABLE public.calendar_connections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    provider text DEFAULT 'google_calendar'::text NOT NULL,
    account_email text,
    sync_token text,
    created_at timestamp with time zone DEFAULT now(),
    next_sync_at timestamp with time zone,
    sync_status text DEFAULT 'active'::text,
    access_token text,
    email text,
    refresh_token text,
    expires_at timestamp with time zone,
    granted_scopes text,
    id_token text,
    token_type text,
    last_error text,
    last_sync_at timestamp with time zone,
    token_expires_at timestamp with time zone,
    CONSTRAINT calendar_connections_pkey PRIMARY KEY (id),
    CONSTRAINT calendar_connections_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT unique_user_provider UNIQUE (user_id, provider)
);
ALTER TABLE public.calendar_connections ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.categories
-- ============================================================
CREATE TABLE public.categories (
    id uuid DEFAULT uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    name text NOT NULL,
    color_hex text DEFAULT '#64748B'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT categories_color_hex_chk CHECK (color_hex ~ '^#[0-9A-Fa-f]{6}$'::text),
    CONSTRAINT categories_name_not_blank_chk CHECK (length(TRIM(BOTH FROM name)) > 0),
    CONSTRAINT categories_pkey PRIMARY KEY (id),
    CONSTRAINT categories_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.completion_events
-- ============================================================
CREATE TABLE public.completion_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    sub_task_id uuid,
    workspace_id uuid,
    completed_at timestamp with time zone DEFAULT now() NOT NULL,
    event_day date GENERATED ALWAYS AS (((completed_at AT TIME ZONE 'UTC'::text))::date) STORED,
    source_surface text DEFAULT 'dashboard'::text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT completion_events_pkey PRIMARY KEY (id),
    CONSTRAINT completion_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.completion_events ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.fixed_classes
-- ============================================================
CREATE TABLE public.fixed_classes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    class_name text NOT NULL,
    day_of_week text NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    location text,
    color_hex text DEFAULT '#6200EE'::text,
    created_at timestamp with time zone DEFAULT now(),
    class_type text,
    CONSTRAINT classes_pkey PRIMARY KEY (id),
    CONSTRAINT classes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.fixed_classes ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.focus_sessions
-- ============================================================
CREATE TABLE public.focus_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    duration_minutes integer NOT NULL,
    xp integer DEFAULT 0 NOT NULL,
    completed_at timestamp with time zone DEFAULT now() NOT NULL,
    session_day date GENERATED ALWAYS AS (((completed_at AT TIME ZONE 'UTC'::text))::date) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT focus_sessions_duration_chk CHECK (duration_minutes > 0 AND duration_minutes <= 1440),
    CONSTRAINT focus_sessions_pkey PRIMARY KEY (id),
    CONSTRAINT focus_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT focus_sessions_xp_chk CHECK (xp >= 0)
);
ALTER TABLE public.focus_sessions ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.managed_schedule_events
-- ============================================================
CREATE TABLE public.managed_schedule_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    sub_task_id uuid,
    connection_id uuid,
    external_event_id text,
    start_time timestamp with time zone,
    end_time timestamp with time zone,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()),
    CONSTRAINT managed_schedule_events_pkey PRIMARY KEY (id)
);
-- Row Level Security is disabled on public.managed_schedule_events;

-- ============================================================
-- TABLE: public.notification_preferences
-- ============================================================
CREATE TABLE public.notification_preferences (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    task_id text,
    reminder_time timestamp with time zone,
    is_enabled boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT notification_preferences_pkey PRIMARY KEY (id),
    CONSTRAINT notification_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.orchestration_runs
-- ============================================================
CREATE TABLE public.orchestration_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    kind text NOT NULL,
    status text NOT NULL,
    attempt_count integer DEFAULT 1 NOT NULL,
    idempotency_key text NOT NULL,
    payload_hash text NOT NULL,
    request_id text,
    source_surface text DEFAULT 'dashboard'::text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    result_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    warning_summary jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_message text,
    queued_at timestamp with time zone DEFAULT now() NOT NULL,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    lease_owner text,
    lease_expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT orchestration_runs_attempt_count_chk CHECK (attempt_count >= 1),
    CONSTRAINT orchestration_runs_pkey PRIMARY KEY (id),
    CONSTRAINT orchestration_runs_status_chk CHECK (status = ANY (ARRAY['QUEUED'::text, 'PROCESSING'::text, 'COMPLETED'::text, 'COMPLETED_WITH_WARNINGS'::text, 'FAILED'::text, 'FAILED_TIMEOUT'::text, 'CANCELLED'::text])),
    CONSTRAINT orchestration_runs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.orchestration_runs ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.primary_tasks
-- ============================================================
CREATE TABLE public.primary_tasks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    title text NOT NULL,
    total_subtasks integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    description text,
    status text DEFAULT 'pending'::text NOT NULL,
    due_date timestamp with time zone,
    task_type text DEFAULT 'general'::text NOT NULL,
    category_id uuid,
    notes text,
    CONSTRAINT primary_tasks_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
    CONSTRAINT primary_tasks_pkey PRIMARY KEY (id),
    CONSTRAINT primary_tasks_status_architecture_chk CHECK (status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'archived'::text, 'Pending'::text, 'In Progress'::text, 'Completed'::text, 'TODO'::text, 'IN_PROGRESS'::text, 'DONE'::text, 'CANCELLED'::text])),
    CONSTRAINT primary_tasks_task_type_chk CHECK (task_type = ANY (ARRAY['general'::text, 'exam'::text, 'assignment'::text, 'event'::text, 'reminder'::text])),
    CONSTRAINT primary_tasks_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.primary_tasks ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.productivity_daily_stats
-- ============================================================
CREATE TABLE public.productivity_daily_stats (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    stat_day date NOT NULL,
    completed_count integer DEFAULT 0 NOT NULL,
    open_count integer DEFAULT 0 NOT NULL,
    completed_minutes integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT productivity_daily_stats_pkey PRIMARY KEY (id),
    CONSTRAINT productivity_daily_stats_user_day_uidx UNIQUE (user_id, stat_day),
    CONSTRAINT productivity_daily_stats_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.productivity_daily_stats ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.reminder_deliveries
-- ============================================================
CREATE TABLE public.reminder_deliveries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    reminder_job_id uuid NOT NULL,
    user_id uuid NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    delivered_at timestamp with time zone,
    error_message text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    channel text DEFAULT 'push'::text NOT NULL,
    delivery_state text DEFAULT 'pending'::text,
    payload jsonb,
    read_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT reminder_deliveries_channel_chk CHECK (channel = ANY (ARRAY['inbox'::text, 'email'::text, 'push'::text])),
    CONSTRAINT reminder_deliveries_job_id_fkey FOREIGN KEY (reminder_job_id) REFERENCES reminder_jobs(id) ON DELETE CASCADE,
    CONSTRAINT reminder_deliveries_pkey PRIMARY KEY (id),
    CONSTRAINT reminder_deliveries_state_chk CHECK (delivery_state = ANY (ARRAY['pending'::text, 'sent'::text, 'read'::text, 'failed'::text])),
    CONSTRAINT reminder_deliveries_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.reminder_deliveries ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.reminder_jobs
-- ============================================================
CREATE TABLE public.reminder_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    task_id text,
    reminder_at timestamp with time zone,
    status text DEFAULT 'pending'::text,
    created_at timestamp with time zone DEFAULT now(),
    channel text,
    payload jsonb,
    sub_task_id text,
    title text,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT reminder_jobs_pkey PRIMARY KEY (id),
    CONSTRAINT reminder_jobs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.reminder_jobs ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.streak_snapshots
-- ============================================================
CREATE TABLE public.streak_snapshots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    streak_day date NOT NULL,
    streak_count integer DEFAULT 0 NOT NULL,
    longest_streak integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT streak_snapshots_pkey PRIMARY KEY (id),
    CONSTRAINT streak_snapshots_user_day_uidx UNIQUE (user_id, streak_day),
    CONSTRAINT streak_snapshots_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.streak_snapshots ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.sub_tasks
-- ============================================================
CREATE TABLE public.sub_tasks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    primary_task_id uuid,
    title text NOT NULL,
    due_date date,
    is_completed boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    user_id uuid,
    estimated_minutes integer DEFAULT 30,
    status text DEFAULT 'pending'::text,
    scheduled_date date,
    scheduled_start_time time without time zone,
    scheduled_end_time time without time zone,
    priority_band text,
    priority_reason text,
    CONSTRAINT sub_tasks_pkey PRIMARY KEY (id),
    CONSTRAINT sub_tasks_primary_task_id_fkey FOREIGN KEY (primary_task_id) REFERENCES primary_tasks(id) ON DELETE CASCADE,
    CONSTRAINT sub_tasks_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.sub_tasks ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.tags
-- ============================================================
CREATE TABLE public.tags (
    id uuid DEFAULT uuid_generate_v4() NOT NULL,
    user_id uuid NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tags_name_not_blank_chk CHECK (length(TRIM(BOTH FROM name)) > 0),
    CONSTRAINT tags_pkey PRIMARY KEY (id),
    CONSTRAINT tags_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.task_tags_map
-- ============================================================
CREATE TABLE public.task_tags_map (
    task_id uuid,
    primary_task_id uuid,
    tag_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT task_tags_map_one_task_chk CHECK (task_id IS NOT NULL AND primary_task_id IS NULL OR task_id IS NULL AND primary_task_id IS NOT NULL),
    CONSTRAINT task_tags_map_primary_task_id_fkey FOREIGN KEY (primary_task_id) REFERENCES primary_tasks(id) ON DELETE CASCADE,
    CONSTRAINT task_tags_map_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE,
    CONSTRAINT task_tags_map_task_id_fkey FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);
ALTER TABLE public.task_tags_map ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.tasks
-- ============================================================
CREATE TABLE public.tasks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    title text NOT NULL,
    description text,
    due_date date,
    priority_level text,
    is_completed boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    status text DEFAULT 'pending'::text NOT NULL,
    task_type text DEFAULT 'general'::text NOT NULL,
    category_id uuid,
    notes text,
    CONSTRAINT tasks_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
    CONSTRAINT tasks_pkey PRIMARY KEY (id),
    CONSTRAINT tasks_priority_level_check CHECK (priority_level = ANY (ARRAY['High'::text, 'Medium'::text, 'Low'::text])),
    CONSTRAINT tasks_status_architecture_chk CHECK (status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'archived'::text, 'Pending'::text, 'In Progress'::text, 'Completed'::text, 'TODO'::text, 'IN_PROGRESS'::text, 'DONE'::text, 'CANCELLED'::text])),
    CONSTRAINT tasks_task_type_chk CHECK (task_type = ANY (ARRAY['general'::text, 'exam'::text, 'assignment'::text, 'event'::text, 'reminder'::text])),
    CONSTRAINT tasks_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.user_badges
-- ============================================================
CREATE TABLE public.user_badges (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    badge_id uuid NOT NULL,
    awarded_at timestamp with time zone DEFAULT now() NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT user_badges_badge_id_fkey FOREIGN KEY (badge_id) REFERENCES badges(id) ON DELETE CASCADE,
    CONSTRAINT user_badges_pkey PRIMARY KEY (id),
    CONSTRAINT user_badges_user_badge_uidx UNIQUE (user_id, badge_id),
    CONSTRAINT user_badges_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.user_badges ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.user_preferences
-- ============================================================
CREATE TABLE public.user_preferences (
    user_id uuid NOT NULL,
    wake_time time without time zone DEFAULT '07:00:00'::time without time zone,
    sleep_time time without time zone DEFAULT '23:00:00'::time without time zone,
    focus_duration_minutes integer DEFAULT 25,
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT user_preferences_pkey PRIMARY KEY (user_id),
    CONSTRAINT user_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.user_profiles
-- ============================================================
CREATE TABLE public.user_profiles (
    id uuid NOT NULL,
    full_name text,
    avatar_url text,
    university text,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    user_id uuid,
    CONSTRAINT user_profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id),
    CONSTRAINT user_profiles_pkey PRIMARY KEY (id),
    CONSTRAINT user_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT user_profiles_user_id_key UNIQUE (user_id)
);
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- TABLE: public.web_push_subscriptions
-- ============================================================
CREATE TABLE public.web_push_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    endpoint text NOT NULL,
    p256dh text NOT NULL,
    auth text NOT NULL,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT web_push_subscriptions_endpoint_key UNIQUE (endpoint),
    CONSTRAINT web_push_subscriptions_pkey PRIMARY KEY (id),
    CONSTRAINT web_push_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.web_push_subscriptions ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.badges
-- ============================================================
-- No foreign keys

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.calendar_busy_intervals
-- ============================================================
ALTER TABLE ONLY public.calendar_busy_intervals ADD CONSTRAINT calendar_busy_intervals_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.calendar_calendars
-- ============================================================
-- No foreign keys

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.calendar_connections
-- ============================================================
ALTER TABLE ONLY public.calendar_connections ADD CONSTRAINT calendar_connections_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.categories
-- ============================================================
ALTER TABLE ONLY public.categories ADD CONSTRAINT categories_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.completion_events
-- ============================================================
ALTER TABLE ONLY public.completion_events ADD CONSTRAINT completion_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.fixed_classes
-- ============================================================
ALTER TABLE ONLY public.fixed_classes ADD CONSTRAINT classes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.focus_sessions
-- ============================================================
ALTER TABLE ONLY public.focus_sessions ADD CONSTRAINT focus_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.managed_schedule_events
-- ============================================================
-- No foreign keys

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.notification_preferences
-- ============================================================
ALTER TABLE ONLY public.notification_preferences ADD CONSTRAINT notification_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.orchestration_runs
-- ============================================================
ALTER TABLE ONLY public.orchestration_runs ADD CONSTRAINT orchestration_runs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.primary_tasks
-- ============================================================
ALTER TABLE ONLY public.primary_tasks ADD CONSTRAINT primary_tasks_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.primary_tasks ADD CONSTRAINT primary_tasks_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.productivity_daily_stats
-- ============================================================
ALTER TABLE ONLY public.productivity_daily_stats ADD CONSTRAINT productivity_daily_stats_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.reminder_deliveries
-- ============================================================
ALTER TABLE ONLY public.reminder_deliveries ADD CONSTRAINT reminder_deliveries_job_id_fkey FOREIGN KEY (reminder_job_id) REFERENCES reminder_jobs(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.reminder_deliveries ADD CONSTRAINT reminder_deliveries_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.reminder_jobs
-- ============================================================
ALTER TABLE ONLY public.reminder_jobs ADD CONSTRAINT reminder_jobs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.streak_snapshots
-- ============================================================
ALTER TABLE ONLY public.streak_snapshots ADD CONSTRAINT streak_snapshots_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.sub_tasks
-- ============================================================
ALTER TABLE ONLY public.sub_tasks ADD CONSTRAINT sub_tasks_primary_task_id_fkey FOREIGN KEY (primary_task_id) REFERENCES primary_tasks(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.sub_tasks ADD CONSTRAINT sub_tasks_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.tags
-- ============================================================
ALTER TABLE ONLY public.tags ADD CONSTRAINT tags_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.task_tags_map
-- ============================================================
ALTER TABLE ONLY public.task_tags_map ADD CONSTRAINT task_tags_map_primary_task_id_fkey FOREIGN KEY (primary_task_id) REFERENCES primary_tasks(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.task_tags_map ADD CONSTRAINT task_tags_map_tag_id_fkey FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.task_tags_map ADD CONSTRAINT task_tags_map_task_id_fkey FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.tasks
-- ============================================================
ALTER TABLE ONLY public.tasks ADD CONSTRAINT tasks_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.tasks ADD CONSTRAINT tasks_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.user_badges
-- ============================================================
ALTER TABLE ONLY public.user_badges ADD CONSTRAINT user_badges_badge_id_fkey FOREIGN KEY (badge_id) REFERENCES badges(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.user_badges ADD CONSTRAINT user_badges_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.user_preferences
-- ============================================================
ALTER TABLE ONLY public.user_preferences ADD CONSTRAINT user_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.user_profiles
-- ============================================================
ALTER TABLE ONLY public.user_profiles ADD CONSTRAINT user_profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id);
ALTER TABLE ONLY public.user_profiles ADD CONSTRAINT user_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- FOREIGN KEY RELATIONSHIPS: public.web_push_subscriptions
-- ============================================================
ALTER TABLE ONLY public.web_push_subscriptions ADD CONSTRAINT web_push_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- INDEXES: public.badges
-- ============================================================
CREATE UNIQUE INDEX badges_badge_key_key ON public.badges USING btree (badge_key);
CREATE UNIQUE INDEX badges_pkey ON public.badges USING btree (id);

-- ============================================================
-- INDEXES: public.calendar_busy_intervals
-- ============================================================
CREATE UNIQUE INDEX calendar_busy_intervals_pkey ON public.calendar_busy_intervals USING btree (id);

-- ============================================================
-- INDEXES: public.calendar_calendars
-- ============================================================
CREATE UNIQUE INDEX calendar_calendars_pkey ON public.calendar_calendars USING btree (id);
CREATE UNIQUE INDEX unique_user_calendar ON public.calendar_calendars USING btree (user_id, provider_calendar_id);

-- ============================================================
-- INDEXES: public.calendar_connections
-- ============================================================
CREATE UNIQUE INDEX calendar_connections_pkey ON public.calendar_connections USING btree (id);
CREATE UNIQUE INDEX unique_user_provider ON public.calendar_connections USING btree (user_id, provider);

-- ============================================================
-- INDEXES: public.categories
-- ============================================================
CREATE UNIQUE INDEX categories_pkey ON public.categories USING btree (id);
CREATE INDEX categories_user_id_idx ON public.categories USING btree (user_id);
CREATE UNIQUE INDEX categories_user_name_unique_idx ON public.categories USING btree (user_id, lower(name));

-- ============================================================
-- INDEXES: public.completion_events
-- ============================================================
CREATE UNIQUE INDEX completion_events_pkey ON public.completion_events USING btree (id);
CREATE INDEX completion_events_user_day_idx ON public.completion_events USING btree (user_id, completed_at DESC);
CREATE UNIQUE INDEX completion_events_user_task_uidx ON public.completion_events USING btree (user_id, sub_task_id) WHERE (sub_task_id IS NOT NULL);

-- ============================================================
-- INDEXES: public.fixed_classes
-- ============================================================
CREATE UNIQUE INDEX classes_pkey ON public.fixed_classes USING btree (id);

-- ============================================================
-- INDEXES: public.focus_sessions
-- ============================================================
CREATE UNIQUE INDEX focus_sessions_pkey ON public.focus_sessions USING btree (id);
CREATE INDEX focus_sessions_user_completed_idx ON public.focus_sessions USING btree (user_id, completed_at DESC);

-- ============================================================
-- INDEXES: public.managed_schedule_events
-- ============================================================
CREATE UNIQUE INDEX managed_schedule_events_pkey ON public.managed_schedule_events USING btree (id);

-- ============================================================
-- INDEXES: public.notification_preferences
-- ============================================================
CREATE UNIQUE INDEX notification_preferences_pkey ON public.notification_preferences USING btree (id);

-- ============================================================
-- INDEXES: public.orchestration_runs
-- ============================================================
CREATE UNIQUE INDEX orchestration_runs_pkey ON public.orchestration_runs USING btree (id);
CREATE INDEX orchestration_runs_status_lease_idx ON public.orchestration_runs USING btree (status, lease_expires_at);
CREATE UNIQUE INDEX orchestration_runs_user_idempotency_uidx ON public.orchestration_runs USING btree (user_id, idempotency_key);
CREATE INDEX orchestration_runs_user_updated_idx ON public.orchestration_runs USING btree (user_id, updated_at DESC);

-- ============================================================
-- INDEXES: public.primary_tasks
-- ============================================================
CREATE INDEX primary_tasks_category_id_idx ON public.primary_tasks USING btree (category_id);
CREATE UNIQUE INDEX primary_tasks_pkey ON public.primary_tasks USING btree (id);
CREATE INDEX primary_tasks_status_idx ON public.primary_tasks USING btree (status);
CREATE INDEX primary_tasks_task_type_idx ON public.primary_tasks USING btree (task_type);

-- ============================================================
-- INDEXES: public.productivity_daily_stats
-- ============================================================
CREATE UNIQUE INDEX productivity_daily_stats_pkey ON public.productivity_daily_stats USING btree (id);
CREATE INDEX productivity_daily_stats_user_day_idx ON public.productivity_daily_stats USING btree (user_id, stat_day DESC);
CREATE UNIQUE INDEX productivity_daily_stats_user_day_uidx ON public.productivity_daily_stats USING btree (user_id, stat_day);

-- ============================================================
-- INDEXES: public.reminder_deliveries
-- ============================================================
CREATE UNIQUE INDEX reminder_deliveries_job_channel_uidx ON public.reminder_deliveries USING btree (reminder_job_id, channel) WHERE (reminder_job_id IS NOT NULL);
CREATE UNIQUE INDEX reminder_deliveries_pkey ON public.reminder_deliveries USING btree (id);
CREATE INDEX reminder_deliveries_user_created_idx ON public.reminder_deliveries USING btree (user_id, created_at DESC);

-- ============================================================
-- INDEXES: public.reminder_jobs
-- ============================================================
CREATE UNIQUE INDEX reminder_jobs_pkey ON public.reminder_jobs USING btree (id);
CREATE INDEX reminder_jobs_user_reminder_idx ON public.reminder_jobs USING btree (user_id, reminder_at);

-- ============================================================
-- INDEXES: public.streak_snapshots
-- ============================================================
CREATE UNIQUE INDEX streak_snapshots_pkey ON public.streak_snapshots USING btree (id);
CREATE INDEX streak_snapshots_user_day_idx ON public.streak_snapshots USING btree (user_id, streak_day DESC);
CREATE UNIQUE INDEX streak_snapshots_user_day_uidx ON public.streak_snapshots USING btree (user_id, streak_day);

-- ============================================================
-- INDEXES: public.sub_tasks
-- ============================================================
CREATE UNIQUE INDEX sub_tasks_pkey ON public.sub_tasks USING btree (id);
CREATE INDEX sub_tasks_user_id_idx ON public.sub_tasks USING btree (user_id);

-- ============================================================
-- INDEXES: public.tags
-- ============================================================
CREATE UNIQUE INDEX tags_pkey ON public.tags USING btree (id);
CREATE INDEX tags_user_id_idx ON public.tags USING btree (user_id);
CREATE UNIQUE INDEX tags_user_name_unique_idx ON public.tags USING btree (user_id, lower(name));

-- ============================================================
-- INDEXES: public.task_tags_map
-- ============================================================
CREATE UNIQUE INDEX task_tags_map_primary_task_tag_unique_idx ON public.task_tags_map USING btree (primary_task_id, tag_id) WHERE (primary_task_id IS NOT NULL);
CREATE INDEX task_tags_map_tag_id_idx ON public.task_tags_map USING btree (tag_id);
CREATE UNIQUE INDEX task_tags_map_task_tag_unique_idx ON public.task_tags_map USING btree (task_id, tag_id) WHERE (task_id IS NOT NULL);

-- ============================================================
-- INDEXES: public.tasks
-- ============================================================
CREATE INDEX tasks_category_id_idx ON public.tasks USING btree (category_id);
CREATE UNIQUE INDEX tasks_pkey ON public.tasks USING btree (id);
CREATE INDEX tasks_status_idx ON public.tasks USING btree (status);
CREATE INDEX tasks_task_type_idx ON public.tasks USING btree (task_type);

-- ============================================================
-- INDEXES: public.user_badges
-- ============================================================
CREATE UNIQUE INDEX user_badges_pkey ON public.user_badges USING btree (id);
CREATE INDEX user_badges_user_awarded_idx ON public.user_badges USING btree (user_id, awarded_at DESC);
CREATE UNIQUE INDEX user_badges_user_badge_uidx ON public.user_badges USING btree (user_id, badge_id);

-- ============================================================
-- INDEXES: public.user_preferences
-- ============================================================
CREATE UNIQUE INDEX user_preferences_pkey ON public.user_preferences USING btree (user_id);

-- ============================================================
-- INDEXES: public.user_profiles
-- ============================================================
CREATE UNIQUE INDEX user_profiles_pkey ON public.user_profiles USING btree (id);
CREATE UNIQUE INDEX user_profiles_user_id_key ON public.user_profiles USING btree (user_id);

-- ============================================================
-- INDEXES: public.web_push_subscriptions
-- ============================================================
CREATE UNIQUE INDEX web_push_subscriptions_endpoint_key ON public.web_push_subscriptions USING btree (endpoint);
CREATE UNIQUE INDEX web_push_subscriptions_pkey ON public.web_push_subscriptions USING btree (id);
CREATE INDEX web_push_subscriptions_user_updated_idx ON public.web_push_subscriptions USING btree (user_id, updated_at DESC);

-- ============================================================
-- RLS POLICIES: public.badges
-- ============================================================
CREATE POLICY "Authenticated users can view badges" ON public.badges
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING (true)
;

-- ============================================================
-- RLS POLICIES: public.calendar_busy_intervals
-- ============================================================
CREATE POLICY "Users can delete their own calendar busy intervals" ON public.calendar_busy_intervals
    AS PERMISSIVE
    FOR DELETE
    TO public
    USING ((auth.uid() = user_id))
;

CREATE POLICY "Users can insert their own calendar busy intervals" ON public.calendar_busy_intervals
    AS PERMISSIVE
    FOR INSERT
    TO public
    WITH CHECK ((auth.uid() = user_id))
;

CREATE POLICY "Users can update their own calendar busy intervals" ON public.calendar_busy_intervals
    AS PERMISSIVE
    FOR UPDATE
    TO public
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

CREATE POLICY "Users can view their own calendar busy intervals" ON public.calendar_busy_intervals
    AS PERMISSIVE
    FOR SELECT
    TO public
    USING ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.calendar_calendars
-- ============================================================
-- No RLS policies

-- ============================================================
-- RLS POLICIES: public.calendar_connections
-- ============================================================
CREATE POLICY "Users can manage their own calendar connections" ON public.calendar_connections
    AS PERMISSIVE
    FOR ALL
    TO public
    USING ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.categories
-- ============================================================
CREATE POLICY "Users can manage their own categories" ON public.categories
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((user_id = auth.uid()))
    WITH CHECK ((user_id = auth.uid()))
;

-- ============================================================
-- RLS POLICIES: public.completion_events
-- ============================================================
CREATE POLICY completion_events_self_manage ON public.completion_events
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.fixed_classes
-- ============================================================
CREATE POLICY "Select fixed_classes" ON public.fixed_classes
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING ((auth.uid() = user_id))
;

CREATE POLICY "Users can manage their own fixed classes" ON public.fixed_classes
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.focus_sessions
-- ============================================================
CREATE POLICY "Users can view their own focus sessions" ON public.focus_sessions
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING ((user_id = auth.uid()))
;

-- ============================================================
-- RLS POLICIES: public.managed_schedule_events
-- ============================================================
-- No RLS policies

-- ============================================================
-- RLS POLICIES: public.notification_preferences
-- ============================================================
CREATE POLICY "Select notification_prefs" ON public.notification_preferences
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING ((auth.uid() = user_id))
;

CREATE POLICY "Users can manage their own notification preferences" ON public.notification_preferences
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

CREATE POLICY notification_preferences_self_manage ON public.notification_preferences
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.orchestration_runs
-- ============================================================
CREATE POLICY "Users can manage their own orchestration runs" ON public.orchestration_runs
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

CREATE POLICY orchestration_runs_self_manage ON public.orchestration_runs
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.primary_tasks
-- ============================================================
CREATE POLICY "Select primary_tasks" ON public.primary_tasks
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING ((auth.uid() = user_id))
;

CREATE POLICY "Users can manage their own primary_tasks" ON public.primary_tasks
    AS PERMISSIVE
    FOR ALL
    TO public
    USING ((auth.uid() = user_id))
;

CREATE POLICY "Users can see their own primary tasks" ON public.primary_tasks
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.productivity_daily_stats
-- ============================================================
CREATE POLICY productivity_daily_stats_self_manage ON public.productivity_daily_stats
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.reminder_deliveries
-- ============================================================
CREATE POLICY "Users can delete their own reminder deliveries" ON public.reminder_deliveries
    AS PERMISSIVE
    FOR DELETE
    TO public
    USING ((auth.uid() = user_id))
;

CREATE POLICY "Users can insert their own reminder deliveries" ON public.reminder_deliveries
    AS PERMISSIVE
    FOR INSERT
    TO public
    WITH CHECK ((auth.uid() = user_id))
;

CREATE POLICY "Users can update their own reminder deliveries" ON public.reminder_deliveries
    AS PERMISSIVE
    FOR UPDATE
    TO public
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

CREATE POLICY "Users can view their own reminder deliveries" ON public.reminder_deliveries
    AS PERMISSIVE
    FOR SELECT
    TO public
    USING ((auth.uid() = user_id))
;

CREATE POLICY reminder_deliveries_self_manage ON public.reminder_deliveries
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.reminder_jobs
-- ============================================================
CREATE POLICY "Users can manage their own reminder jobs" ON public.reminder_jobs
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

CREATE POLICY reminder_jobs_self_manage ON public.reminder_jobs
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.streak_snapshots
-- ============================================================
CREATE POLICY streak_snapshots_self_manage ON public.streak_snapshots
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.sub_tasks
-- ============================================================
CREATE POLICY "Allow users to insert sub_tasks if they own the primary_task" ON public.sub_tasks
    AS PERMISSIVE
    FOR INSERT
    TO authenticated
    WITH CHECK ((EXISTS ( SELECT 1
   FROM primary_tasks
  WHERE ((primary_tasks.id = sub_tasks.primary_task_id) AND (primary_tasks.user_id = auth.uid())))))
;

CREATE POLICY "Select sub_tasks" ON public.sub_tasks
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING ((user_id = auth.uid()))
;

CREATE POLICY "Users can see their own sub tasks" ON public.sub_tasks
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING ((user_id = auth.uid()))
;

-- ============================================================
-- RLS POLICIES: public.tags
-- ============================================================
CREATE POLICY "Users can manage their own tags" ON public.tags
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((user_id = auth.uid()))
    WITH CHECK ((user_id = auth.uid()))
;

-- ============================================================
-- RLS POLICIES: public.task_tags_map
-- ============================================================
CREATE POLICY "Users can manage tags on their own tasks" ON public.task_tags_map
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING (((EXISTS ( SELECT 1
   FROM tags
  WHERE ((tags.id = task_tags_map.tag_id) AND (tags.user_id = auth.uid())))) AND (((task_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM tasks
  WHERE ((tasks.id = task_tags_map.task_id) AND (tasks.user_id = auth.uid()))))) OR ((primary_task_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM primary_tasks
  WHERE ((primary_tasks.id = task_tags_map.primary_task_id) AND (primary_tasks.user_id = auth.uid()))))))))
    WITH CHECK (((EXISTS ( SELECT 1
   FROM tags
  WHERE ((tags.id = task_tags_map.tag_id) AND (tags.user_id = auth.uid())))) AND (((task_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM tasks
  WHERE ((tasks.id = task_tags_map.task_id) AND (tasks.user_id = auth.uid()))))) OR ((primary_task_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM primary_tasks
  WHERE ((primary_tasks.id = task_tags_map.primary_task_id) AND (primary_tasks.user_id = auth.uid()))))))))
;

-- ============================================================
-- RLS POLICIES: public.tasks
-- ============================================================
CREATE POLICY "Select tasks" ON public.tasks
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING ((auth.uid() = user_id))
;

CREATE POLICY "Users can manage their own tasks" ON public.tasks
    AS PERMISSIVE
    FOR ALL
    TO public
    USING ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.user_badges
-- ============================================================
CREATE POLICY "Users can manage their own badges" ON public.user_badges
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

CREATE POLICY user_badges_self_manage ON public.user_badges
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.user_preferences
-- ============================================================
CREATE POLICY "Users can manage their own preferences" ON public.user_preferences
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

-- ============================================================
-- RLS POLICIES: public.user_profiles
-- ============================================================
CREATE POLICY "Users can manage their own profile" ON public.user_profiles
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = id))
    WITH CHECK ((auth.uid() = id))
;

-- ============================================================
-- RLS POLICIES: public.web_push_subscriptions
-- ============================================================
CREATE POLICY "Users can manage their own web push subscriptions" ON public.web_push_subscriptions
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

CREATE POLICY web_push_subscriptions_self_manage ON public.web_push_subscriptions
    AS PERMISSIVE
    FOR ALL
    TO authenticated
    USING ((auth.uid() = user_id))
    WITH CHECK ((auth.uid() = user_id))
;

-- ============================================================
-- TRIGGERS: public.badges
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.calendar_busy_intervals
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.calendar_calendars
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.calendar_connections
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.categories
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.completion_events
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.fixed_classes
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.focus_sessions
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.managed_schedule_events
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.notification_preferences
-- ============================================================
CREATE TRIGGER set_notification_preferences_updated_at BEFORE UPDATE ON notification_preferences FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TRIGGERS: public.orchestration_runs
-- ============================================================
CREATE TRIGGER set_orchestration_runs_updated_at BEFORE UPDATE ON orchestration_runs FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TRIGGERS: public.primary_tasks
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.productivity_daily_stats
-- ============================================================
CREATE TRIGGER set_productivity_daily_stats_updated_at BEFORE UPDATE ON productivity_daily_stats FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TRIGGERS: public.reminder_deliveries
-- ============================================================
CREATE TRIGGER set_reminder_deliveries_updated_at BEFORE UPDATE ON reminder_deliveries FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TRIGGERS: public.reminder_jobs
-- ============================================================
CREATE TRIGGER set_reminder_jobs_updated_at BEFORE UPDATE ON reminder_jobs FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TRIGGERS: public.streak_snapshots
-- ============================================================
CREATE TRIGGER set_streak_snapshots_updated_at BEFORE UPDATE ON streak_snapshots FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- TRIGGERS: public.sub_tasks
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.tags
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.task_tags_map
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.tasks
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.user_badges
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.user_preferences
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.user_profiles
-- ============================================================
-- No triggers

-- ============================================================
-- TRIGGERS: public.web_push_subscriptions
-- ============================================================
CREATE TRIGGER set_web_push_subscriptions_updated_at BEFORE UPDATE ON web_push_subscriptions FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- FUNCTIONS REFERENCING: public.badges
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.calendar_busy_intervals
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.calendar_calendars
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.calendar_connections
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.categories
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.completion_events
-- ============================================================
-- Function: public.complete_focus_session(p_user_id uuid, p_duration_minutes integer, p_xp integer, p_completed_at timestamp with time zone)
CREATE OR REPLACE FUNCTION public.complete_focus_session(p_user_id uuid, p_duration_minutes integer, p_xp integer DEFAULT 0, p_completed_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


-- ============================================================
-- FUNCTIONS REFERENCING: public.fixed_classes
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.focus_sessions
-- ============================================================
-- Function: public.complete_focus_session(p_user_id uuid, p_duration_minutes integer, p_xp integer, p_completed_at timestamp with time zone)
CREATE OR REPLACE FUNCTION public.complete_focus_session(p_user_id uuid, p_duration_minutes integer, p_xp integer DEFAULT 0, p_completed_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


-- ============================================================
-- FUNCTIONS REFERENCING: public.managed_schedule_events
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.notification_preferences
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.orchestration_runs
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.primary_tasks
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.productivity_daily_stats
-- ============================================================
-- Function: public.complete_focus_session(p_user_id uuid, p_duration_minutes integer, p_xp integer, p_completed_at timestamp with time zone)
CREATE OR REPLACE FUNCTION public.complete_focus_session(p_user_id uuid, p_duration_minutes integer, p_xp integer DEFAULT 0, p_completed_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


-- ============================================================
-- FUNCTIONS REFERENCING: public.reminder_deliveries
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.reminder_jobs
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.streak_snapshots
-- ============================================================
-- Function: public.complete_focus_session(p_user_id uuid, p_duration_minutes integer, p_xp integer, p_completed_at timestamp with time zone)
CREATE OR REPLACE FUNCTION public.complete_focus_session(p_user_id uuid, p_duration_minutes integer, p_xp integer DEFAULT 0, p_completed_at timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$


-- ============================================================
-- FUNCTIONS REFERENCING: public.sub_tasks
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.tags
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.task_tags_map
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.tasks
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.user_badges
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.user_preferences
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.user_profiles
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- FUNCTIONS REFERENCING: public.web_push_subscriptions
-- ============================================================
-- No ordinary functions found referencing table name in function body

-- ============================================================
-- STORAGE BUCKETS
-- ============================================================
-- No storage buckets

-- ============================================================
-- EDGE FUNCTIONS
-- ============================================================
-- No edge functions returned by Supabase project metadata.