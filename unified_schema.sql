--
-- UNIFIED DATABASE SCHEMA
-- Merged from web_schema_dump.sql (project: udgiccpslmoeoizyskdyf) and mobile_schema_dump.sql
-- Generated: 2026-06-10
--
-- COMPARISON RESULTS
-- ==================
-- 1. Shared table with different columns: tasks (completely different column sets - see table def)
-- 2. Web-only tables (13): workspaces, workspace_members, workspace_invites, profiles, chats,
--    messages, notifications, workspace_files, workspace_logs, workspace_storage_locations,
--    workspace_integrations, external_sync_transactions, external_sync_transaction_items
-- 3. Mobile-only tables (23): badges, calendar_busy_intervals, calendar_calendars,
--    calendar_connections, categories, completion_events, fixed_classes, focus_sessions,
--    managed_schedule_events, notification_preferences, orchestration_runs, primary_tasks,
--    productivity_daily_stats, reminder_deliveries, reminder_jobs, streak_snapshots, sub_tasks,
--    tags, task_tags_map, user_badges, user_preferences, user_profiles, web_push_subscriptions
-- 4. Column type mismatches: tasks table merged as superset (all columns from both schemas)
-- ==================

-- ============================================================================
-- EXTENSIONS
-- ============================================================================
-- extensions.pgcrypto         1.3
-- extensions.uuid-ossp        1.1
-- extensions.pg_stat_statements 1.11
-- extensions.plpgsql          1.0
-- vault.supabase_vault        0.3.1

-- ============================================================================
-- ENUM TYPES (auth, realtime, storage)
-- ============================================================================

CREATE TYPE auth.aal_level AS ENUM ('aal1', 'aal2', 'aal3');
CREATE TYPE auth.code_challenge_method AS ENUM ('s256', 'plain');
CREATE TYPE auth.factor_status AS ENUM ('unverified', 'verified');
CREATE TYPE auth.factor_type AS ENUM ('totp', 'webauthn', 'phone');
CREATE TYPE auth.oauth_authorization_status AS ENUM ('pending', 'approved', 'denied', 'expired');
CREATE TYPE auth.oauth_client_type AS ENUM ('public', 'confidential');
CREATE TYPE auth.oauth_registration_type AS ENUM ('dynamic', 'manual');
CREATE TYPE auth.oauth_response_type AS ENUM ('code');
CREATE TYPE auth.one_time_token_type AS ENUM ('confirmation_token', 'reauthentication_token', 'recovery_token', 'email_change_token_new', 'email_change_token_current', 'phone_change_token');

CREATE TYPE realtime.action AS ENUM ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'ERROR');
CREATE TYPE realtime.equality_op AS ENUM ('eq', 'neq', 'lt', 'lte', 'gt', 'gte', 'in');

CREATE TYPE storage.buckettype AS ENUM ('STANDARD', 'ANALYTICS', 'VECTOR');


-- ============================================================================
-- TABLE: public.badges (mobile)
-- ============================================================================
CREATE TABLE public.badges (
    id          uuid DEFAULT gen_random_uuid() NOT NULL,
    badge_key   text NOT NULL,
    label       text NOT NULL,
    description text NOT NULL,
    tone        text DEFAULT 'secondary'::text NOT NULL,
    created_at  timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT badges_badge_key_key UNIQUE (badge_key),
    CONSTRAINT badges_pkey         PRIMARY KEY (id)
);
ALTER TABLE public.badges ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX badges_badge_key_key ON public.badges USING btree (badge_key);
CREATE UNIQUE INDEX badges_pkey         ON public.badges USING btree (id);
CREATE POLICY "Authenticated users can view badges" ON public.badges FOR SELECT TO authenticated USING (true);


-- ============================================================================
-- TABLE: public.calendar_busy_intervals (mobile)
-- ============================================================================
CREATE TABLE public.calendar_busy_intervals (
    id                  uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id             uuid NOT NULL,
    starts_at           timestamptz NOT NULL,
    ends_at             timestamptz NOT NULL,
    source              text NOT NULL,
    external_event_id   text,
    created_at          timestamptz DEFAULT now() NOT NULL,
    connection_id       uuid,
    external_calendar_id text,
    start_time          timestamptz,
    end_time            timestamptz,
    CONSTRAINT calendar_busy_intervals_pkey      PRIMARY KEY (id),
    CONSTRAINT calendar_busy_intervals_time_check CHECK (ends_at > starts_at),
    CONSTRAINT calendar_busy_intervals_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.calendar_busy_intervals ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX calendar_busy_intervals_pkey ON public.calendar_busy_intervals USING btree (id);
CREATE POLICY "Users can view their own calendar busy intervals"    ON public.calendar_busy_intervals FOR SELECT   TO public USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own calendar busy intervals"  ON public.calendar_busy_intervals FOR INSERT   TO public WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own calendar busy intervals"  ON public.calendar_busy_intervals FOR UPDATE   TO public USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own calendar busy intervals"  ON public.calendar_busy_intervals FOR DELETE   TO public USING (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.calendar_calendars (mobile)
-- ============================================================================
CREATE TABLE public.calendar_calendars (
    id                   uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id              uuid NOT NULL,
    provider             text,
    provider_calendar_id text,
    summary              text,
    description          text,
    color                text,
    time_zone            text,
    access_role          text,
    sync_token           text,
    is_primary           boolean DEFAULT false,
    created_at           timestamptz DEFAULT timezone('utc'::text, now()),
    updated_at           timestamptz DEFAULT timezone('utc'::text, now()),
    connection_id        uuid,
    background_color     text,
    foreground_color     text,
    color_id             text,
    external_calendar_id text,
    primary_calendar     boolean DEFAULT false,
    selected             boolean DEFAULT true,
    hidden               boolean DEFAULT false,
    CONSTRAINT calendar_calendars_pkey PRIMARY KEY (id),
    CONSTRAINT unique_user_calendar   UNIQUE (user_id, provider_calendar_id)
);
CREATE UNIQUE INDEX calendar_calendars_pkey ON public.calendar_calendars USING btree (id);
CREATE UNIQUE INDEX unique_user_calendar    ON public.calendar_calendars USING btree (user_id, provider_calendar_id);


-- ============================================================================
-- TABLE: public.calendar_connections (mobile)
-- ============================================================================
CREATE TABLE public.calendar_connections (
    id              uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id         uuid NOT NULL,
    provider        text DEFAULT 'google_calendar'::text NOT NULL,
    account_email   text,
    sync_token      text,
    created_at      timestamptz DEFAULT now(),
    next_sync_at    timestamptz,
    sync_status     text DEFAULT 'active'::text,
    access_token    text,
    email           text,
    refresh_token   text,
    expires_at      timestamptz,
    granted_scopes  text,
    id_token        text,
    token_type      text,
    last_error      text,
    last_sync_at    timestamptz,
    token_expires_at timestamptz,
    CONSTRAINT calendar_connections_pkey       PRIMARY KEY (id),
    CONSTRAINT calendar_connections_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT unique_user_provider             UNIQUE (user_id, provider)
);
ALTER TABLE public.calendar_connections ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX calendar_connections_pkey ON public.calendar_connections USING btree (id);
CREATE UNIQUE INDEX unique_user_provider      ON public.calendar_connections USING btree (user_id, provider);
CREATE POLICY "Users can manage their own calendar connections" ON public.calendar_connections FOR ALL TO public USING (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.categories (mobile)
-- ============================================================================
CREATE TABLE public.categories (
    id         uuid DEFAULT uuid_generate_v4() NOT NULL,
    user_id    uuid NOT NULL,
    name       text NOT NULL,
    color_hex  text DEFAULT '#64748B'::text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT categories_pkey            PRIMARY KEY (id),
    CONSTRAINT categories_color_hex_chk   CHECK (color_hex ~ '^#[0-9A-Fa-f]{6}$'::text),
    CONSTRAINT categories_name_not_blank_chk CHECK (length(TRIM(BOTH FROM name)) > 0),
    CONSTRAINT categories_user_id_fkey    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX categories_pkey                  ON public.categories USING btree (id);
CREATE        INDEX categories_user_id_idx           ON public.categories USING btree (user_id);
CREATE UNIQUE INDEX categories_user_name_unique_idx  ON public.categories USING btree (user_id, lower(name));
CREATE POLICY "Users can manage their own categories" ON public.categories FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());


-- ============================================================================
-- TABLE: public.chats (web)
-- ============================================================================
CREATE TABLE public.chats (
    id           uuid NOT NULL DEFAULT gen_random_uuid(),
    user_id      uuid NOT NULL,
    title        text NOT NULL DEFAULT 'New Conversation'::text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    workspace_id uuid,
    CONSTRAINT chats_pkey             PRIMARY KEY (id),
    CONSTRAINT chats_user_id_fkey     FOREIGN KEY (user_id)      REFERENCES auth.users(id)  ON DELETE CASCADE,
    CONSTRAINT chats_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);
ALTER TABLE public.chats ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX chats_pkey                       ON public.chats USING btree (id);
CREATE        INDEX chats_user_id_created_at_idx     ON public.chats USING btree (user_id, created_at DESC);
CREATE        INDEX chats_workspace_id_created_at_idx ON public.chats USING btree (workspace_id, created_at);
CREATE POLICY "Users can select their own chats" ON public.chats FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own chats" ON public.chats FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id) AND ((workspace_id IS NULL) OR (EXISTS (SELECT 1 FROM workspace_members WHERE workspace_members.workspace_id = chats.workspace_id AND workspace_members.user_id = auth.uid())))));
CREATE POLICY "Users can update their own chats" ON public.chats FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own chats" ON public.chats FOR DELETE TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Workspace members can select workspace chats" ON public.chats FOR SELECT TO authenticated USING ((workspace_id IS NOT NULL) AND (EXISTS (SELECT 1 FROM workspace_members WHERE workspace_members.workspace_id = chats.workspace_id AND workspace_members.user_id = auth.uid())));
CREATE POLICY "Workspace members can insert workspace chats" ON public.chats FOR INSERT TO authenticated WITH CHECK ((workspace_id IS NOT NULL) AND (EXISTS (SELECT 1 FROM workspace_members WHERE workspace_members.workspace_id = chats.workspace_id AND workspace_members.user_id = auth.uid())));
CREATE POLICY "Members can select workspace chats via auth user" ON public.chats FOR SELECT TO authenticated USING ((workspace_id IS NOT NULL) AND (workspace_id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids)));
CREATE POLICY "Members can insert workspace chats via auth user" ON public.chats FOR INSERT TO authenticated WITH CHECK ((workspace_id IS NOT NULL) AND (workspace_id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids)));


-- ============================================================================
-- TABLE: public.completion_events (mobile)
-- ============================================================================
CREATE TABLE public.completion_events (
    id             uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id        uuid NOT NULL,
    sub_task_id    uuid,
    workspace_id   uuid,
    completed_at   timestamptz DEFAULT now() NOT NULL,
    event_day      date GENERATED ALWAYS AS (((completed_at AT TIME ZONE 'UTC'::text))::date) STORED,
    source_surface text DEFAULT 'dashboard'::text NOT NULL,
    payload        jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at     timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT completion_events_pkey       PRIMARY KEY (id),
    CONSTRAINT completion_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.completion_events ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX completion_events_pkey           ON public.completion_events USING btree (id);
CREATE        INDEX completion_events_user_day_idx   ON public.completion_events USING btree (user_id, completed_at DESC);
CREATE UNIQUE INDEX completion_events_user_task_uidx ON public.completion_events USING btree (user_id, sub_task_id) WHERE (sub_task_id IS NOT NULL);
CREATE POLICY completion_events_self_manage ON public.completion_events FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.external_sync_transactions (web)
-- ============================================================================
CREATE TABLE public.external_sync_transactions (
    id                      uuid NOT NULL DEFAULT gen_random_uuid(),
    user_id                 uuid NOT NULL,
    workspace_id            uuid,
    provider                text NOT NULL,
    direction               text NOT NULL DEFAULT 'export'::text,
    status                  text NOT NULL DEFAULT 'pending'::text,
    requested_count         integer NOT NULL DEFAULT 0,
    found_count             integer NOT NULL DEFAULT 0,
    not_found_count         integer NOT NULL DEFAULT 0,
    skipped_duplicate_count integer NOT NULL DEFAULT 0,
    project_created_count   integer NOT NULL DEFAULT 0,
    created_count           integer NOT NULL DEFAULT 0,
    failed_count            integer NOT NULL DEFAULT 0,
    request_task_ids        uuid[] NOT NULL DEFAULT '{}'::uuid[],
    error                   text,
    started_at              timestamptz NOT NULL DEFAULT now(),
    completed_at            timestamptz,
    created_at              timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT external_sync_transactions_pkey               PRIMARY KEY (id),
    CONSTRAINT external_sync_transactions_user_id_fkey       FOREIGN KEY (user_id)      REFERENCES auth.users(id)  ON DELETE CASCADE,
    CONSTRAINT external_sync_transactions_workspace_id_fkey  FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE SET NULL,
    CONSTRAINT external_sync_transactions_provider_check  CHECK (provider = 'todoist'::text),
    CONSTRAINT external_sync_transactions_direction_check CHECK (direction = 'export'::text),
    CONSTRAINT external_sync_transactions_status_check    CHECK (status = ANY (ARRAY['pending'::text, 'completed'::text, 'partial'::text, 'failed'::text])),
    CONSTRAINT external_sync_transactions_requested_count_check         CHECK (requested_count >= 0),
    CONSTRAINT external_sync_transactions_found_count_check             CHECK (found_count >= 0),
    CONSTRAINT external_sync_transactions_not_found_count_check         CHECK (not_found_count >= 0),
    CONSTRAINT external_sync_transactions_skipped_duplicate_count_check CHECK (skipped_duplicate_count >= 0),
    CONSTRAINT external_sync_transactions_project_created_count_check   CHECK (project_created_count >= 0),
    CONSTRAINT external_sync_transactions_created_count_check           CHECK (created_count >= 0),
    CONSTRAINT external_sync_transactions_failed_count_check            CHECK (failed_count >= 0)
);
ALTER TABLE public.external_sync_transactions ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX external_sync_transactions_pkey                      ON public.external_sync_transactions USING btree (id);
CREATE        INDEX external_sync_transactions_user_provider_created_idx ON public.external_sync_transactions USING btree (user_id, provider, created_at DESC);
CREATE        INDEX external_sync_transactions_workspace_created_idx     ON public.external_sync_transactions USING btree (workspace_id, created_at DESC);
CREATE POLICY "External sync transactions are selectable by owner or app admin" ON public.external_sync_transactions FOR SELECT TO authenticated USING ((auth.uid() = user_id) OR is_app_admin());


-- ============================================================================
-- TABLE: public.external_sync_transaction_items (web)
-- ============================================================================
CREATE TABLE public.external_sync_transaction_items (
    id             uuid NOT NULL DEFAULT gen_random_uuid(),
    transaction_id uuid NOT NULL,
    task_id        uuid NOT NULL,
    user_id        uuid NOT NULL,
    provider       text NOT NULL,
    status         text NOT NULL,
    external_id    text,
    project_id     text,
    error          text,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT external_sync_transaction_items_pkey                        PRIMARY KEY (id),
    CONSTRAINT external_sync_transaction_items_transaction_id_task_id_key UNIQUE (transaction_id, task_id),
    CONSTRAINT external_sync_transaction_items_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES external_sync_transactions(id) ON DELETE CASCADE,
    CONSTRAINT external_sync_transaction_items_task_id_fkey        FOREIGN KEY (task_id)        REFERENCES tasks(id) ON DELETE CASCADE,
    CONSTRAINT external_sync_transaction_items_user_id_fkey        FOREIGN KEY (user_id)        REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT external_sync_transaction_items_provider_check CHECK (provider = 'todoist'::text),
    CONSTRAINT external_sync_transaction_items_status_check   CHECK (status = ANY (ARRAY['queued'::text, 'skipped_already_exported'::text, 'skipped_pending_reconciliation'::text, 'invalid'::text, 'exported'::text, 'failed'::text, 'reconciliation_needed'::text]))
);
ALTER TABLE public.external_sync_transaction_items ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX external_sync_transaction_items_pkey                      ON public.external_sync_transaction_items USING btree (id);
CREATE UNIQUE INDEX external_sync_transaction_items_transaction_id_task_id_key ON public.external_sync_transaction_items USING btree (transaction_id, task_id);
CREATE UNIQUE INDEX external_sync_transaction_items_active_export_uidx        ON public.external_sync_transaction_items USING btree (task_id, provider) WHERE (status = 'queued'::text);
CREATE        INDEX external_sync_transaction_items_transaction_idx           ON public.external_sync_transaction_items USING btree (transaction_id);
CREATE        INDEX external_sync_transaction_items_task_provider_created_idx ON public.external_sync_transaction_items USING btree (task_id, provider, created_at DESC);
CREATE POLICY "External sync transaction items are selectable by owner or app" ON public.external_sync_transaction_items FOR SELECT TO authenticated USING ((auth.uid() = user_id) OR is_app_admin());


-- ============================================================================
-- TABLE: public.fixed_classes (mobile)
-- ============================================================================
CREATE TABLE public.fixed_classes (
    id          uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id     uuid NOT NULL,
    class_name  text NOT NULL,
    day_of_week text NOT NULL,
    start_time  time without time zone NOT NULL,
    end_time    time without time zone NOT NULL,
    location    text,
    color_hex   text DEFAULT '#6200EE'::text,
    created_at  timestamptz DEFAULT now(),
    class_type  text,
    CONSTRAINT classes_pkey        PRIMARY KEY (id),
    CONSTRAINT classes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.fixed_classes ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX classes_pkey ON public.fixed_classes USING btree (id);
CREATE POLICY "Select fixed_classes"                       ON public.fixed_classes FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can manage their own fixed classes"  ON public.fixed_classes FOR ALL    TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.focus_sessions (mobile)
-- ============================================================================
CREATE TABLE public.focus_sessions (
    id               uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id          uuid NOT NULL,
    duration_minutes integer NOT NULL,
    xp               integer DEFAULT 0 NOT NULL,
    completed_at     timestamptz DEFAULT now() NOT NULL,
    session_day      date GENERATED ALWAYS AS (((completed_at AT TIME ZONE 'UTC'::text))::date) STORED,
    created_at       timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT focus_sessions_pkey         PRIMARY KEY (id),
    CONSTRAINT focus_sessions_duration_chk CHECK (duration_minutes > 0 AND duration_minutes <= 1440),
    CONSTRAINT focus_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT focus_sessions_xp_chk       CHECK (xp >= 0)
);
ALTER TABLE public.focus_sessions ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX focus_sessions_pkey               ON public.focus_sessions USING btree (id);
CREATE        INDEX focus_sessions_user_completed_idx ON public.focus_sessions USING btree (user_id, completed_at DESC);
CREATE POLICY "Users can view their own focus sessions" ON public.focus_sessions FOR SELECT TO authenticated USING (user_id = auth.uid());


-- ============================================================================
-- TABLE: public.managed_schedule_events (mobile)
-- ============================================================================
CREATE TABLE public.managed_schedule_events (
    id                uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id           uuid NOT NULL,
    sub_task_id       uuid,
    connection_id     uuid,
    external_event_id text,
    start_time        timestamptz,
    end_time          timestamptz,
    created_at        timestamptz DEFAULT timezone('utc'::text, now()),
    CONSTRAINT managed_schedule_events_pkey PRIMARY KEY (id)
);
CREATE UNIQUE INDEX managed_schedule_events_pkey ON public.managed_schedule_events USING btree (id);


-- ============================================================================
-- TABLE: public.messages (web)
-- ============================================================================
CREATE TABLE public.messages (
    id           uuid NOT NULL DEFAULT gen_random_uuid(),
    chat_id      uuid NOT NULL,
    role         text NOT NULL,
    content      text NOT NULL,
    message_type text NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    user_id      uuid,
    CONSTRAINT messages_pkey             PRIMARY KEY (id),
    CONSTRAINT messages_chat_id_fkey     FOREIGN KEY (chat_id) REFERENCES chats(id)    ON DELETE CASCADE,
    CONSTRAINT messages_user_id_fkey     FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE SET NULL,
    CONSTRAINT messages_role_check       CHECK (role = ANY (ARRAY['user'::text, 'assistant'::text])),
    CONSTRAINT messages_message_type_check CHECK (message_type = ANY (ARRAY['text'::text, 'task-card'::text]))
);
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX messages_pkey                     ON public.messages USING btree (id);
CREATE        INDEX messages_chat_id_created_at_idx   ON public.messages USING btree (chat_id, created_at);
CREATE        INDEX messages_user_id_idx              ON public.messages USING btree (user_id);
CREATE POLICY "Users can select messages in their own chats"  ON public.messages FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM chats WHERE chats.id = messages.chat_id AND chats.user_id = auth.uid()));
CREATE POLICY "Users can insert messages in their own chats"  ON public.messages FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM chats WHERE chats.id = messages.chat_id AND chats.user_id = auth.uid()));
CREATE POLICY "Users can update messages in their own chats"  ON public.messages FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM chats WHERE chats.id = messages.chat_id AND chats.user_id = auth.uid())) WITH CHECK (EXISTS (SELECT 1 FROM chats WHERE chats.id = messages.chat_id AND chats.user_id = auth.uid()));
CREATE POLICY "Users can delete messages in their own chats"  ON public.messages FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM chats WHERE chats.id = messages.chat_id AND chats.user_id = auth.uid()));
CREATE POLICY "Workspace members can select workspace chat messages" ON public.messages FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM (chats JOIN workspace_members ON workspace_members.workspace_id = chats.workspace_id) WHERE chats.id = messages.chat_id AND chats.workspace_id IS NOT NULL AND workspace_members.user_id = auth.uid()));
CREATE POLICY "Workspace members can insert workspace chat messages" ON public.messages FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM (chats JOIN workspace_members ON workspace_members.workspace_id = chats.workspace_id) WHERE chats.id = messages.chat_id AND chats.workspace_id IS NOT NULL AND workspace_members.user_id = auth.uid()));
CREATE POLICY "Members can select workspace messages via auth user"  ON public.messages FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM chats c WHERE c.id = messages.chat_id AND c.workspace_id IS NOT NULL AND c.workspace_id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids)));
CREATE POLICY "Members can insert workspace messages via auth user"  ON public.messages FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM chats c WHERE c.id = messages.chat_id AND c.workspace_id IS NOT NULL AND c.workspace_id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids)));


-- ============================================================================
-- TABLE: public.notifications (web)
-- ============================================================================
CREATE TABLE public.notifications (
    id         uuid NOT NULL DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL,
    title      text NOT NULL,
    message    text NOT NULL,
    is_read    boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT notifications_pkey         PRIMARY KEY (id),
    CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX notifications_pkey                ON public.notifications USING btree (id);
CREATE        INDEX notifications_user_id_idx         ON public.notifications USING btree (user_id);
CREATE        INDEX notifications_user_created_at_idx ON public.notifications USING btree (user_id, created_at DESC);
CREATE        INDEX notifications_user_unread_idx     ON public.notifications USING btree (user_id, is_read);
CREATE POLICY "Notifications are selectable by owner"   ON public.notifications FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Notifications are updatable by owner"    ON public.notifications FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own notifications" ON public.notifications FOR DELETE TO public        USING (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.notification_preferences (mobile)
-- ============================================================================
CREATE TABLE public.notification_preferences (
    id            uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id       uuid NOT NULL,
    task_id       text,
    reminder_time timestamptz,
    is_enabled    boolean DEFAULT true,
    created_at    timestamptz DEFAULT now(),
    CONSTRAINT notification_preferences_pkey      PRIMARY KEY (id),
    CONSTRAINT notification_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX notification_preferences_pkey ON public.notification_preferences USING btree (id);
CREATE POLICY "Select notification_prefs"                    ON public.notification_preferences FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can manage their own notification preferences" ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY notification_preferences_self_manage           ON public.notification_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.orchestration_runs (mobile)
-- ============================================================================
CREATE TABLE public.orchestration_runs (
    id               uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id          uuid NOT NULL,
    kind             text NOT NULL,
    status           text NOT NULL,
    attempt_count    integer DEFAULT 1 NOT NULL,
    idempotency_key  text NOT NULL,
    payload_hash     text NOT NULL,
    request_id       text,
    source_surface   text DEFAULT 'dashboard'::text NOT NULL,
    payload          jsonb DEFAULT '{}'::jsonb NOT NULL,
    result_payload   jsonb DEFAULT '{}'::jsonb NOT NULL,
    warning_summary  jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_message    text,
    queued_at        timestamptz DEFAULT now() NOT NULL,
    started_at       timestamptz,
    completed_at     timestamptz,
    lease_owner      text,
    lease_expires_at timestamptz,
    created_at       timestamptz DEFAULT now() NOT NULL,
    updated_at       timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT orchestration_runs_pkey            PRIMARY KEY (id),
    CONSTRAINT orchestration_runs_attempt_count_chk CHECK (attempt_count >= 1),
    CONSTRAINT orchestration_runs_status_chk      CHECK (status = ANY (ARRAY['QUEUED'::text, 'PROCESSING'::text, 'COMPLETED'::text, 'COMPLETED_WITH_WARNINGS'::text, 'FAILED'::text, 'FAILED_TIMEOUT'::text, 'CANCELLED'::text])),
    CONSTRAINT orchestration_runs_user_id_fkey    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.orchestration_runs ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX orchestration_runs_pkey                     ON public.orchestration_runs USING btree (id);
CREATE        INDEX orchestration_runs_status_lease_idx         ON public.orchestration_runs USING btree (status, lease_expires_at);
CREATE UNIQUE INDEX orchestration_runs_user_idempotency_uidx    ON public.orchestration_runs USING btree (user_id, idempotency_key);
CREATE        INDEX orchestration_runs_user_updated_idx         ON public.orchestration_runs USING btree (user_id, updated_at DESC);
CREATE POLICY "Users can manage their own orchestration runs"   ON public.orchestration_runs FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY orchestration_runs_self_manage                    ON public.orchestration_runs FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.primary_tasks (mobile)
-- ============================================================================
CREATE TABLE public.primary_tasks (
    id              uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id         uuid,
    title           text NOT NULL,
    total_subtasks  integer DEFAULT 0,
    created_at      timestamptz DEFAULT now(),
    description     text,
    status          text DEFAULT 'pending'::text NOT NULL,
    due_date        timestamptz,
    task_type       text DEFAULT 'general'::text NOT NULL,
    category_id     uuid,
    notes           text,
    CONSTRAINT primary_tasks_pkey                  PRIMARY KEY (id),
    CONSTRAINT primary_tasks_category_id_fkey      FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
    CONSTRAINT primary_tasks_user_id_fkey          FOREIGN KEY (user_id)     REFERENCES auth.users(id),
    CONSTRAINT primary_tasks_status_architecture_chk CHECK (status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'archived'::text, 'Pending'::text, 'In Progress'::text, 'Completed'::text, 'TODO'::text, 'IN_PROGRESS'::text, 'DONE'::text, 'CANCELLED'::text])),
    CONSTRAINT primary_tasks_task_type_chk         CHECK (task_type = ANY (ARRAY['general'::text, 'exam'::text, 'assignment'::text, 'event'::text, 'reminder'::text]))
);
ALTER TABLE public.primary_tasks ENABLE ROW LEVEL SECURITY;
CREATE        INDEX primary_tasks_category_id_idx ON public.primary_tasks USING btree (category_id);
CREATE UNIQUE INDEX primary_tasks_pkey            ON public.primary_tasks USING btree (id);
CREATE        INDEX primary_tasks_status_idx      ON public.primary_tasks USING btree (status);
CREATE        INDEX primary_tasks_task_type_idx   ON public.primary_tasks USING btree (task_type);
CREATE POLICY "Select primary_tasks"                  ON public.primary_tasks FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can manage their own primary_tasks" ON public.primary_tasks FOR ALL TO public USING (auth.uid() = user_id);
CREATE POLICY "Users can see their own primary tasks"    ON public.primary_tasks FOR SELECT TO authenticated USING (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.productivity_daily_stats (mobile)
-- ============================================================================
CREATE TABLE public.productivity_daily_stats (
    id                uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id           uuid NOT NULL,
    stat_day          date NOT NULL,
    completed_count   integer DEFAULT 0 NOT NULL,
    open_count        integer DEFAULT 0 NOT NULL,
    completed_minutes integer DEFAULT 0 NOT NULL,
    created_at        timestamptz DEFAULT now() NOT NULL,
    updated_at        timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT productivity_daily_stats_pkey         PRIMARY KEY (id),
    CONSTRAINT productivity_daily_stats_user_day_uidx UNIQUE (user_id, stat_day),
    CONSTRAINT productivity_daily_stats_user_id_fkey  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.productivity_daily_stats ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX productivity_daily_stats_pkey           ON public.productivity_daily_stats USING btree (id);
CREATE        INDEX productivity_daily_stats_user_day_idx   ON public.productivity_daily_stats USING btree (user_id, stat_day DESC);
CREATE UNIQUE INDEX productivity_daily_stats_user_day_uidx  ON public.productivity_daily_stats USING btree (user_id, stat_day);
CREATE POLICY productivity_daily_stats_self_manage ON public.productivity_daily_stats FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.profiles (web) -- user profile extension table
-- ============================================================================
CREATE TABLE public.profiles (
    id                       uuid NOT NULL DEFAULT gen_random_uuid(),
    user_id                  uuid NOT NULL,
    current_streak           integer NOT NULL DEFAULT 0,
    last_task_completed_at   date,
    badges                   text[] NOT NULL DEFAULT '{}'::text[],
    full_name                text,
    avatar_url               text,
    moodle_calendar_url      text,
    moodle_token_secret_id   uuid,
    moodle_token_updated_at  timestamptz,
    todoist_token_secret_id  uuid,
    todoist_token_updated_at timestamptz,
    university_type          text,
    gpa                      numeric,
    scholarship_threshold    numeric,
    CONSTRAINT profiles_pkey                          PRIMARY KEY (id),
    CONSTRAINT profiles_user_id_key                   UNIQUE (user_id),
    CONSTRAINT profiles_user_id_fkey                  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT profiles_current_streak_check          CHECK (current_streak >= 0),
    CONSTRAINT profiles_gpa_valid_range               CHECK ((gpa IS NULL) OR ((gpa >= (0)::numeric) AND (gpa <= 4.0))),
    CONSTRAINT profiles_scholarship_threshold_valid_range CHECK ((scholarship_threshold IS NULL) OR ((scholarship_threshold >= (0)::numeric) AND (scholarship_threshold <= 4.0)))
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX profiles_pkey         ON public.profiles USING btree (id);
CREATE UNIQUE INDEX profiles_user_id_key  ON public.profiles USING btree (user_id);
CREATE        INDEX profiles_user_id_idx  ON public.profiles USING btree (user_id);
CREATE POLICY "Profiles are viewable by everyone" ON public.profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "Profiles are selectable by owner"  ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Profiles are updatable by owner"   ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own profile"      ON public.profiles FOR UPDATE TO public        USING (auth.uid() = id) WITH CHECK (auth.uid() = id);


-- ============================================================================
-- TABLE: public.reminder_deliveries (mobile)
-- ============================================================================
CREATE TABLE public.reminder_deliveries (
    id              uuid DEFAULT gen_random_uuid() NOT NULL,
    reminder_job_id uuid NOT NULL,
    user_id         uuid NOT NULL,
    status          text DEFAULT 'pending'::text NOT NULL,
    delivered_at    timestamptz,
    error_message   text,
    created_at      timestamptz DEFAULT now() NOT NULL,
    channel         text DEFAULT 'push'::text NOT NULL,
    delivery_state  text DEFAULT 'pending'::text,
    payload         jsonb,
    read_at         timestamptz,
    updated_at      timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT reminder_deliveries_pkey          PRIMARY KEY (id),
    CONSTRAINT reminder_deliveries_channel_chk   CHECK (channel = ANY (ARRAY['inbox'::text, 'email'::text, 'push'::text])),
    CONSTRAINT reminder_deliveries_state_chk     CHECK (delivery_state = ANY (ARRAY['pending'::text, 'sent'::text, 'read'::text, 'failed'::text])),
    CONSTRAINT reminder_deliveries_job_id_fkey   FOREIGN KEY (reminder_job_id) REFERENCES reminder_jobs(id) ON DELETE CASCADE,
    CONSTRAINT reminder_deliveries_user_id_fkey  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.reminder_deliveries ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX reminder_deliveries_job_channel_uidx ON public.reminder_deliveries USING btree (reminder_job_id, channel) WHERE (reminder_job_id IS NOT NULL);
CREATE UNIQUE INDEX reminder_deliveries_pkey             ON public.reminder_deliveries USING btree (id);
CREATE        INDEX reminder_deliveries_user_created_idx ON public.reminder_deliveries USING btree (user_id, created_at DESC);
CREATE POLICY "Users can view their own reminder deliveries"    ON public.reminder_deliveries FOR SELECT TO public USING (auth.uid() = user_id);
CREATE POLICY "Users can insert their own reminder deliveries"  ON public.reminder_deliveries FOR INSERT TO public WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update their own reminder deliveries"  ON public.reminder_deliveries FOR UPDATE TO public USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete their own reminder deliveries"  ON public.reminder_deliveries FOR DELETE TO public USING (auth.uid() = user_id);
CREATE POLICY reminder_deliveries_self_manage ON public.reminder_deliveries FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.reminder_jobs (mobile)
-- ============================================================================
CREATE TABLE public.reminder_jobs (
    id          uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id     uuid NOT NULL,
    task_id     text,
    reminder_at timestamptz,
    status      text DEFAULT 'pending'::text,
    created_at  timestamptz DEFAULT now(),
    channel     text,
    payload     jsonb,
    sub_task_id text,
    title       text,
    updated_at  timestamptz DEFAULT now(),
    CONSTRAINT reminder_jobs_pkey       PRIMARY KEY (id),
    CONSTRAINT reminder_jobs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.reminder_jobs ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX reminder_jobs_pkey              ON public.reminder_jobs USING btree (id);
CREATE        INDEX reminder_jobs_user_reminder_idx ON public.reminder_jobs USING btree (user_id, reminder_at);
CREATE POLICY "Users can manage their own reminder jobs" ON public.reminder_jobs FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY reminder_jobs_self_manage                  ON public.reminder_jobs FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.streak_snapshots (mobile)
-- ============================================================================
CREATE TABLE public.streak_snapshots (
    id             uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id        uuid NOT NULL,
    streak_day     date NOT NULL,
    streak_count   integer DEFAULT 0 NOT NULL,
    longest_streak integer DEFAULT 0 NOT NULL,
    created_at     timestamptz DEFAULT now() NOT NULL,
    updated_at     timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT streak_snapshots_pkey          PRIMARY KEY (id),
    CONSTRAINT streak_snapshots_user_day_uidx UNIQUE (user_id, streak_day),
    CONSTRAINT streak_snapshots_user_id_fkey  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.streak_snapshots ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX streak_snapshots_pkey            ON public.streak_snapshots USING btree (id);
CREATE        INDEX streak_snapshots_user_day_idx    ON public.streak_snapshots USING btree (user_id, streak_day DESC);
CREATE UNIQUE INDEX streak_snapshots_user_day_uidx   ON public.streak_snapshots USING btree (user_id, streak_day);
CREATE POLICY streak_snapshots_self_manage ON public.streak_snapshots FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.sub_tasks (mobile)
-- ============================================================================
CREATE TABLE public.sub_tasks (
    id                   uuid DEFAULT gen_random_uuid() NOT NULL,
    primary_task_id      uuid,
    title                text NOT NULL,
    due_date             date,
    is_completed         boolean DEFAULT false,
    created_at           timestamptz DEFAULT now(),
    user_id              uuid,
    estimated_minutes    integer DEFAULT 30,
    status               text DEFAULT 'pending'::text,
    scheduled_date       date,
    scheduled_start_time time without time zone,
    scheduled_end_time   time without time zone,
    priority_band        text,
    priority_reason      text,
    CONSTRAINT sub_tasks_pkey                  PRIMARY KEY (id),
    CONSTRAINT sub_tasks_primary_task_id_fkey  FOREIGN KEY (primary_task_id) REFERENCES primary_tasks(id) ON DELETE CASCADE,
    CONSTRAINT sub_tasks_user_id_fkey          FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.sub_tasks ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX sub_tasks_pkey         ON public.sub_tasks USING btree (id);
CREATE        INDEX sub_tasks_user_id_idx  ON public.sub_tasks USING btree (user_id);
CREATE POLICY "Select sub_tasks" ON public.sub_tasks FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Users can see their own sub tasks" ON public.sub_tasks FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "Allow users to insert sub_tasks if they own the primary_task" ON public.sub_tasks FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM primary_tasks WHERE primary_tasks.id = sub_tasks.primary_task_id AND primary_tasks.user_id = auth.uid()));


-- ============================================================================
-- TABLE: public.tags (mobile)
-- ============================================================================
CREATE TABLE public.tags (
    id         uuid DEFAULT uuid_generate_v4() NOT NULL,
    user_id    uuid NOT NULL,
    name       text NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT tags_pkey               PRIMARY KEY (id),
    CONSTRAINT tags_name_not_blank_chk CHECK (length(TRIM(BOTH FROM name)) > 0),
    CONSTRAINT tags_user_id_fkey       FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX tags_pkey                  ON public.tags USING btree (id);
CREATE        INDEX tags_user_id_idx           ON public.tags USING btree (user_id);
CREATE UNIQUE INDEX tags_user_name_unique_idx  ON public.tags USING btree (user_id, lower(name));
CREATE POLICY "Users can manage their own tags" ON public.tags FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());


-- ============================================================================
-- TABLE: public.task_tags_map (mobile)
-- ============================================================================
CREATE TABLE public.task_tags_map (
    task_id          uuid,
    primary_task_id  uuid,
    tag_id           uuid NOT NULL,
    created_at       timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT task_tags_map_one_task_chk CHECK ((task_id IS NOT NULL AND primary_task_id IS NULL) OR (task_id IS NULL AND primary_task_id IS NOT NULL)),
    CONSTRAINT task_tags_map_tag_id_fkey          FOREIGN KEY (tag_id)           REFERENCES tags(id) ON DELETE CASCADE,
    CONSTRAINT task_tags_map_task_id_fkey         FOREIGN KEY (task_id)          REFERENCES tasks(id) ON DELETE CASCADE,
    CONSTRAINT task_tags_map_primary_task_id_fkey FOREIGN KEY (primary_task_id)  REFERENCES primary_tasks(id) ON DELETE CASCADE
);
ALTER TABLE public.task_tags_map ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX task_tags_map_task_tag_unique_idx          ON public.task_tags_map USING btree (task_id, tag_id) WHERE (task_id IS NOT NULL);
CREATE UNIQUE INDEX task_tags_map_primary_task_tag_unique_idx  ON public.task_tags_map USING btree (primary_task_id, tag_id) WHERE (primary_task_id IS NOT NULL);
CREATE        INDEX task_tags_map_tag_id_idx                   ON public.task_tags_map USING btree (tag_id);
CREATE POLICY "Users can manage tags on their own tasks" ON public.task_tags_map FOR ALL TO authenticated USING ((EXISTS (SELECT 1 FROM tags WHERE tags.id = task_tags_map.tag_id AND tags.user_id = auth.uid())) AND (((task_id IS NOT NULL) AND (EXISTS (SELECT 1 FROM tasks WHERE tasks.id = task_tags_map.task_id AND tasks.user_id = auth.uid()))) OR ((primary_task_id IS NOT NULL) AND (EXISTS (SELECT 1 FROM primary_tasks WHERE primary_tasks.id = task_tags_map.primary_task_id AND primary_tasks.user_id = auth.uid()))))) WITH CHECK ((EXISTS (SELECT 1 FROM tags WHERE tags.id = task_tags_map.tag_id AND tags.user_id = auth.uid())) AND (((task_id IS NOT NULL) AND (EXISTS (SELECT 1 FROM tasks WHERE tasks.id = task_tags_map.task_id AND tasks.user_id = auth.uid()))) OR ((primary_task_id IS NOT NULL) AND (EXISTS (SELECT 1 FROM primary_tasks WHERE primary_tasks.id = task_tags_map.primary_task_id AND primary_tasks.user_id = auth.uid())))));


-- ============================================================================
-- TABLE: public.user_badges (mobile)
-- ============================================================================
CREATE TABLE public.user_badges (
    id         uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id    uuid NOT NULL,
    badge_id   uuid NOT NULL,
    awarded_at timestamptz DEFAULT now() NOT NULL,
    payload    jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT user_badges_pkey           PRIMARY KEY (id),
    CONSTRAINT user_badges_user_badge_uidx UNIQUE (user_id, badge_id),
    CONSTRAINT user_badges_badge_id_fkey  FOREIGN KEY (badge_id) REFERENCES badges(id) ON DELETE CASCADE,
    CONSTRAINT user_badges_user_id_fkey   FOREIGN KEY (user_id)   REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.user_badges ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX user_badges_pkey               ON public.user_badges USING btree (id);
CREATE        INDEX user_badges_user_awarded_idx   ON public.user_badges USING btree (user_id, awarded_at DESC);
CREATE UNIQUE INDEX user_badges_user_badge_uidx    ON public.user_badges USING btree (user_id, badge_id);
CREATE POLICY "Users can manage their own badges" ON public.user_badges FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY user_badges_self_manage             ON public.user_badges FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.user_preferences (mobile)
-- ============================================================================
CREATE TABLE public.user_preferences (
    user_id                 uuid NOT NULL,
    wake_time               time without time zone DEFAULT '07:00:00'::time without time zone,
    sleep_time              time without time zone DEFAULT '23:00:00'::time without time zone,
    focus_duration_minutes  integer DEFAULT 25,
    updated_at              timestamptz DEFAULT now(),
    CONSTRAINT user_preferences_pkey       PRIMARY KEY (user_id),
    CONSTRAINT user_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX user_preferences_pkey ON public.user_preferences USING btree (user_id);
CREATE POLICY "Users can manage their own preferences" ON public.user_preferences FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.user_profiles (mobile) -- separate mobile-oriented profile
-- ============================================================================
CREATE TABLE public.user_profiles (
    id          uuid NOT NULL,
    full_name   text,
    avatar_url  text,
    university  text,
    created_at  timestamptz DEFAULT now(),
    updated_at  timestamptz DEFAULT now(),
    user_id     uuid,
    CONSTRAINT user_profiles_pkey        PRIMARY KEY (id),
    CONSTRAINT user_profiles_user_id_key UNIQUE (user_id),
    CONSTRAINT user_profiles_id_fkey     FOREIGN KEY (id)      REFERENCES auth.users(id),
    CONSTRAINT user_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX user_profiles_pkey         ON public.user_profiles USING btree (id);
CREATE UNIQUE INDEX user_profiles_user_id_key  ON public.user_profiles USING btree (user_id);
CREATE POLICY "Users can manage their own profile" ON public.user_profiles FOR ALL TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);


-- ============================================================================
-- TABLE: public.web_push_subscriptions (mobile)
-- ============================================================================
CREATE TABLE public.web_push_subscriptions (
    id         uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id    uuid NOT NULL,
    endpoint   text NOT NULL,
    p256dh     text NOT NULL,
    auth       text NOT NULL,
    user_agent text,
    created_at timestamptz DEFAULT now() NOT NULL,
    updated_at timestamptz DEFAULT now() NOT NULL,
    CONSTRAINT web_push_subscriptions_pkey         PRIMARY KEY (id),
    CONSTRAINT web_push_subscriptions_endpoint_key UNIQUE (endpoint),
    CONSTRAINT web_push_subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
);
ALTER TABLE public.web_push_subscriptions ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX web_push_subscriptions_endpoint_key     ON public.web_push_subscriptions USING btree (endpoint);
CREATE UNIQUE INDEX web_push_subscriptions_pkey             ON public.web_push_subscriptions USING btree (id);
CREATE        INDEX web_push_subscriptions_user_updated_idx ON public.web_push_subscriptions USING btree (user_id, updated_at DESC);
CREATE POLICY "Users can manage their own web push subscriptions" ON public.web_push_subscriptions FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY web_push_subscriptions_self_manage                 ON public.web_push_subscriptions FOR ALL TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);


-- ============================================================================
-- TABLE: public.workspaces (web) -- MUST come before tables with FK to it
-- ============================================================================
CREATE TABLE public.workspaces (
    id          uuid NOT NULL DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    description text,
    slug        text,
    created_at  timestamptz DEFAULT now(),
    created_by  uuid,
    CONSTRAINT workspaces_pkey            PRIMARY KEY (id),
    CONSTRAINT workspaces_slug_key        UNIQUE (slug),
    CONSTRAINT workspaces_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL
);
ALTER TABLE public.workspaces ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX workspaces_pkey     ON public.workspaces USING btree (id);
CREATE UNIQUE INDEX workspaces_slug_key ON public.workspaces USING btree (slug);
CREATE POLICY "Users can create workspaces" ON public.workspaces FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Members can view workspaces via auth user" ON public.workspaces FOR SELECT TO authenticated USING (id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids));
CREATE POLICY "Admins can update workspace via auth user" ON public.workspaces FOR UPDATE TO authenticated USING (EXISTS (SELECT 1 FROM workspace_members wm WHERE wm.workspace_id = workspaces.id AND wm.user_id = auth.uid() AND wm.role = 'admin')) WITH CHECK (EXISTS (SELECT 1 FROM workspace_members wm WHERE wm.workspace_id = workspaces.id AND wm.user_id = auth.uid() AND wm.role = 'admin'));
CREATE POLICY "Admins can delete workspace via auth user" ON public.workspaces FOR DELETE TO authenticated USING (EXISTS (SELECT 1 FROM workspace_members wm WHERE wm.workspace_id = workspaces.id AND wm.user_id = auth.uid() AND wm.role = 'admin'));


-- ============================================================================
-- TABLE: public.workspace_files (web)
-- ============================================================================
CREATE TABLE public.workspace_files (
    id                  uuid NOT NULL DEFAULT gen_random_uuid(),
    workspace_id        uuid NOT NULL,
    name                text NOT NULL,
    type                text NOT NULL DEFAULT 'file'::text,
    size                text,
    url                 text NOT NULL,
    uploaded_by         text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    provider            text NOT NULL DEFAULT 'google_drive'::text,
    status              text NOT NULL DEFAULT 'ready'::text,
    mime_type           text,
    byte_size           bigint,
    uploaded_by_user_id uuid,
    metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
    updated_at          timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workspace_files_pkey              PRIMARY KEY (id),
    CONSTRAINT workspace_files_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    CONSTRAINT workspace_files_status_check      CHECK (status = ANY (ARRAY['pending'::text, 'uploading'::text, 'ready'::text, 'failed'::text, 'deleted'::text]))
);
ALTER TABLE public.workspace_files ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX workspace_files_pkey                         ON public.workspace_files USING btree (id);
CREATE        INDEX workspace_files_workspace_id_created_at_idx  ON public.workspace_files USING btree (workspace_id, created_at DESC);
CREATE        INDEX workspace_files_workspace_status_created_idx ON public.workspace_files USING btree (workspace_id, status, created_at DESC);
CREATE        INDEX workspace_files_metadata_gin_idx             ON public.workspace_files USING gin (metadata);
CREATE POLICY "Workspace members can view files" ON public.workspace_files FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM workspace_members WHERE workspace_members.workspace_id = workspace_files.workspace_id AND workspace_members.user_id = auth.uid()));
CREATE POLICY "Workspace members can add files"  ON public.workspace_files FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM workspace_members WHERE workspace_members.workspace_id = workspace_files.workspace_id AND workspace_members.user_id = auth.uid()));
CREATE POLICY "Members can view workspace files via auth user" ON public.workspace_files FOR SELECT TO authenticated USING (workspace_id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids));
CREATE POLICY "Members can add workspace files via auth user"  ON public.workspace_files FOR INSERT TO authenticated WITH CHECK (workspace_id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids));


-- ============================================================================
-- TABLE: public.workspace_integrations (web)
-- ============================================================================
CREATE TABLE public.workspace_integrations (
    workspace_id          uuid NOT NULL,
    provider              text NOT NULL,
    encrypted_webhook_url text NOT NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workspace_integrations_pkey              PRIMARY KEY (workspace_id, provider),
    CONSTRAINT workspace_integrations_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    CONSTRAINT workspace_integrations_provider_check    CHECK (provider = ANY (ARRAY['slack'::text, 'discord'::text]))
);
ALTER TABLE public.workspace_integrations ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX workspace_integrations_pkey             ON public.workspace_integrations USING btree (workspace_id, provider);
CREATE        INDEX workspace_integrations_workspace_id_idx ON public.workspace_integrations USING btree (workspace_id);
CREATE POLICY "workspace admins can manage integrations" ON public.workspace_integrations FOR ALL TO authenticated USING (EXISTS (SELECT 1 FROM workspace_members wm WHERE wm.workspace_id = workspace_integrations.workspace_id AND wm.user_id = auth.uid() AND wm.role = 'admin')) WITH CHECK (EXISTS (SELECT 1 FROM workspace_members wm WHERE wm.workspace_id = workspace_integrations.workspace_id AND wm.user_id = auth.uid() AND wm.role = 'admin'));
CREATE POLICY "service role can manage integrations"    ON public.workspace_integrations FOR ALL TO service_role USING (true) WITH CHECK (true);


-- ============================================================================
-- TABLE: public.workspace_invites (web)
-- ============================================================================
CREATE TABLE public.workspace_invites (
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    workspace_id    uuid NOT NULL,
    invited_user_id uuid NOT NULL,
    role            text NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    expires_at      timestamptz NOT NULL DEFAULT (now() + '7 days'::interval),
    consumed_at     timestamptz,
    consumed_by     uuid,
    CONSTRAINT workspace_invites_pkey                 PRIMARY KEY (id),
    CONSTRAINT workspace_invites_workspace_id_fkey    FOREIGN KEY (workspace_id)    REFERENCES workspaces(id) ON DELETE CASCADE,
    CONSTRAINT workspace_invites_invited_user_id_fkey FOREIGN KEY (invited_user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT workspace_invites_consumed_by_fkey     FOREIGN KEY (consumed_by)     REFERENCES auth.users(id) ON DELETE SET NULL,
    CONSTRAINT workspace_invites_role_check           CHECK (role = 'member'::text)
);
ALTER TABLE public.workspace_invites ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX workspace_invites_pkey                  ON public.workspace_invites USING btree (id);
CREATE UNIQUE INDEX workspace_invites_one_active_invite_idx ON public.workspace_invites USING btree (workspace_id, invited_user_id) WHERE (consumed_at IS NULL);
CREATE        INDEX workspace_invites_active_lookup_idx     ON public.workspace_invites USING btree (workspace_id, invited_user_id, expires_at) WHERE (consumed_at IS NULL);


-- ============================================================================
-- TABLE: public.workspace_logs (web)
-- ============================================================================
CREATE TABLE public.workspace_logs (
    id           uuid NOT NULL DEFAULT gen_random_uuid(),
    workspace_id uuid NOT NULL,
    type         text NOT NULL DEFAULT 'message'::text,
    user_name    text NOT NULL DEFAULT 'Workspace member'::text,
    initials     text NOT NULL DEFAULT 'WM'::text,
    action       text NOT NULL,
    target       text,
    created_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workspace_logs_pkey              PRIMARY KEY (id),
    CONSTRAINT workspace_logs_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);
ALTER TABLE public.workspace_logs ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX workspace_logs_pkey                          ON public.workspace_logs USING btree (id);
CREATE        INDEX workspace_logs_workspace_id_created_at_idx   ON public.workspace_logs USING btree (workspace_id, created_at DESC);
CREATE POLICY "Workspace members can view logs" ON public.workspace_logs FOR SELECT TO authenticated USING (EXISTS (SELECT 1 FROM workspace_members WHERE workspace_members.workspace_id = workspace_logs.workspace_id AND workspace_members.user_id = auth.uid()));
CREATE POLICY "Workspace members can add logs"  ON public.workspace_logs FOR INSERT TO authenticated WITH CHECK (EXISTS (SELECT 1 FROM workspace_members WHERE workspace_members.workspace_id = workspace_logs.workspace_id AND workspace_members.user_id = auth.uid()));
CREATE POLICY "Members can view workspace logs via auth user" ON public.workspace_logs FOR SELECT TO authenticated USING (workspace_id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids));
CREATE POLICY "Members can add workspace logs via auth user"  ON public.workspace_logs FOR INSERT TO authenticated WITH CHECK (workspace_id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids));


-- ============================================================================
-- TABLE: public.workspace_members (web)
-- ============================================================================
CREATE TABLE public.workspace_members (
    workspace_id uuid NOT NULL,
    user_id      uuid NOT NULL,
    role         text DEFAULT 'member'::text,
    joined_at    timestamptz DEFAULT now(),
    CONSTRAINT workspace_members_pkey              PRIMARY KEY (workspace_id, user_id),
    CONSTRAINT workspace_members_workspace_id_fkey FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE,
    CONSTRAINT workspace_members_user_id_fkey      FOREIGN KEY (user_id)      REFERENCES auth.users(id) ON DELETE CASCADE,
    CONSTRAINT workspace_members_role_check        CHECK (role = ANY (ARRAY['admin'::text, 'member'::text]))
);
ALTER TABLE public.workspace_members ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX workspace_members_pkey ON public.workspace_members USING btree (workspace_id, user_id);
CREATE POLICY "Users can add workspace members"      ON public.workspace_members FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "Invited users can accept own invites" ON public.workspace_members FOR INSERT TO authenticated WITH CHECK ((role = 'member'::text) AND (user_id = auth.uid()) AND (EXISTS (SELECT 1 FROM workspace_invites wi WHERE wi.workspace_id = workspace_members.workspace_id AND wi.invited_user_id = auth.uid() AND wi.consumed_at IS NULL AND wi.expires_at > now())));
CREATE POLICY "Members can view workspace members via auth user" ON public.workspace_members FOR SELECT TO authenticated USING (workspace_id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids));
CREATE POLICY "Members can leave workspace via auth user" ON public.workspace_members FOR DELETE TO authenticated USING ((user_id = auth.uid()) OR (EXISTS (SELECT 1 FROM workspace_members wm WHERE wm.workspace_id = workspace_members.workspace_id AND wm.user_id = auth.uid() AND wm.role = 'admin')));


-- ============================================================================
-- TABLE: public.workspace_storage_locations (web)
-- ============================================================================
CREATE TABLE public.workspace_storage_locations (
    id           uuid NOT NULL DEFAULT gen_random_uuid(),
    workspace_id uuid NOT NULL,
    provider     text NOT NULL,
    external_id  text NOT NULL,
    display_name text,
    metadata     jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by   uuid,
    created_at   timestamptz NOT NULL DEFAULT now(),
    updated_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT workspace_storage_locations_pkey                    PRIMARY KEY (id),
    CONSTRAINT workspace_storage_locations_workspace_id_provider_key UNIQUE (workspace_id, provider),
    CONSTRAINT workspace_storage_locations_workspace_id_fkey       FOREIGN KEY (workspace_id) REFERENCES workspaces(id) ON DELETE CASCADE
);
ALTER TABLE public.workspace_storage_locations ENABLE ROW LEVEL SECURITY;
CREATE UNIQUE INDEX workspace_storage_locations_pkey                      ON public.workspace_storage_locations USING btree (id);
CREATE UNIQUE INDEX workspace_storage_locations_workspace_id_provider_key ON public.workspace_storage_locations USING btree (workspace_id, provider);
CREATE        INDEX workspace_storage_locations_workspace_idx             ON public.workspace_storage_locations USING btree (workspace_id);
CREATE POLICY "Members can view workspace storage locations via auth user" ON public.workspace_storage_locations FOR SELECT TO authenticated USING (workspace_id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids));


-- ============================================================================
-- TABLE: public.tasks (MERGED - superset of web + mobile columns)
-- ============================================================================
-- MERGE NOTES:
--   Web-only columns:       estimated_duration, course, updated_at,
--                           workspace_id, assigned_to, external_source, external_id, metadata
--   Mobile-only columns:    description, priority_level(text), is_completed, task_type,
--                           category_id, notes
--   Conflicts resolved:
--     - user_id: web NOT NULL wins (CASCADE delete), mobile was nullable (no CASCADE) -> kept NOT NULL with CASCADE
--     - due_date: web NOT NULL, mobile nullable -> relaxed to nullable to accommodate mobile
    --     - status: web default 'TODO', mobile default 'pending' -> kept 'TODO' (web), CHECK includes mobile architecture values
--     - priority (web smallint) vs priority_level (mobile text): merged into single priority_level text column with 'High'/'Medium'/'Low'
CREATE TABLE public.tasks (
    -- Core identity
    id                 uuid NOT NULL DEFAULT gen_random_uuid(),
    user_id            uuid NOT NULL,

    -- Web columns
    title              text NOT NULL,
    due_date           date,                          -- relaxed from web NOT NULL to nullable (mobile compatibility)
    estimated_duration text,                          -- web only
    priority_level     text NOT NULL DEFAULT 'Medium', -- merged from web priority(smallint) and mobile priority_level(text)
    status             text NOT NULL DEFAULT 'TODO'::text, -- web default preserved
    course             text,                          -- web only
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    workspace_id       uuid,                          -- web only
    assigned_to        uuid,                          -- web only
    external_source    text,                          -- web only
    external_id        text,                          -- web only
    metadata           jsonb NOT NULL DEFAULT '{}'::jsonb, -- web only

    -- Mobile columns
    description        text,                          -- mobile only
    is_completed       boolean DEFAULT false,         -- mobile only
    task_type          text DEFAULT 'general'::text,  -- mobile only
    category_id        uuid,                          -- mobile only
    notes              text,                          -- mobile only

    -- Constraints
    CONSTRAINT tasks_pkey              PRIMARY KEY (id),
    CONSTRAINT tasks_user_id_fkey      FOREIGN KEY (user_id)      REFERENCES auth.users(id)  ON DELETE CASCADE,
    CONSTRAINT tasks_workspace_id_fkey FOREIGN KEY (workspace_id)  REFERENCES workspaces(id) ON DELETE CASCADE,
    CONSTRAINT tasks_assigned_to_fkey  FOREIGN KEY (assigned_to)   REFERENCES profiles(id)   ON DELETE SET NULL,
    CONSTRAINT tasks_category_id_fkey  FOREIGN KEY (category_id)   REFERENCES categories(id) ON DELETE SET NULL,   -- mobile FK
    CONSTRAINT tasks_priority_level_check CHECK (priority_level = ANY (ARRAY['High'::text, 'Medium'::text, 'Low'::text])),
    CONSTRAINT tasks_status_check      CHECK (status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'archived'::text, 'Pending'::text, 'In Progress'::text, 'Completed'::text, 'TODO'::text, 'IN_PROGRESS'::text, 'DONE'::text, 'CANCELLED'::text])),
    CONSTRAINT tasks_task_type_chk     CHECK (task_type IS NULL OR task_type = ANY (ARRAY['general'::text, 'exam'::text, 'assignment'::text, 'event'::text, 'reminder'::text])) -- mobile
);
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

-- Web indexes
CREATE UNIQUE INDEX tasks_pkey             ON public.tasks USING btree (id);
CREATE        INDEX tasks_user_id_idx      ON public.tasks USING btree (user_id);
CREATE        INDEX tasks_user_due_date_idx ON public.tasks USING btree (user_id, due_date);
CREATE        INDEX tasks_user_status_idx  ON public.tasks USING btree (user_id, status);
CREATE UNIQUE INDEX tasks_user_external_event_uidx ON public.tasks USING btree (user_id, external_source, external_id) WHERE ((external_source IS NOT NULL) AND (external_id IS NOT NULL));

-- Mobile indexes
CREATE        INDEX tasks_category_id_idx  ON public.tasks USING btree (category_id);
CREATE        INDEX tasks_status_idx       ON public.tasks USING btree (status);
CREATE        INDEX tasks_task_type_idx    ON public.tasks USING btree (task_type);

-- RLS Policies (merged: web policies for workspace collaboration + mobile policies for personal tasks)
CREATE POLICY "Tasks are selectable by owner or app admin"                 ON public.tasks FOR SELECT TO authenticated USING ((auth.uid() = user_id) OR is_app_admin());
CREATE POLICY "Tasks are insertable by owner or app admin"                 ON public.tasks FOR INSERT TO authenticated WITH CHECK ((auth.uid() = user_id) OR is_app_admin());
CREATE POLICY "Tasks are updatable by owner or app admin"                  ON public.tasks FOR UPDATE TO authenticated USING ((auth.uid() = user_id) OR is_app_admin()) WITH CHECK ((auth.uid() = user_id) OR is_app_admin());
CREATE POLICY "Tasks are deletable by owner or app admin"                  ON public.tasks FOR DELETE TO authenticated USING ((auth.uid() = user_id) OR is_app_admin());
CREATE POLICY "Safe users can manage own or workspace tasks"               ON public.tasks FOR ALL    TO authenticated USING ((user_id = auth.uid()) OR (workspace_id IN (SELECT get_my_workspace_ids() AS get_my_workspace_ids)));
CREATE POLICY "Select tasks"                                                ON public.tasks FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can manage their own tasks"                           ON public.tasks FOR ALL    TO public USING (auth.uid() = user_id);


-- ============================================================================
-- FUNCTIONS (from both schemas)
-- ============================================================================

-- Web functions (referenced by RLS policies and triggers)
-- FUNCTION: get_my_workspace_ids() RETURNS SETOF uuid -- SECURITY DEFINER, STABLE
-- FUNCTION: create_new_workspace(workspace_name text) RETURNS uuid -- SECURITY DEFINER
-- FUNCTION: initialize_chat_session_tx(p_title text, p_message_content text) RETURNS uuid -- SECURITY DEFINER
-- FUNCTION: is_app_admin() RETURNS boolean -- STABLE
-- FUNCTION: set_updated_at() RETURNS trigger -- BEFORE UPDATE trigger helper
-- FUNCTION: create_task_completed_notification() RETURNS trigger -- SECURITY DEFINER
-- FUNCTION: set_external_sync_transaction_item_updated_at() RETURNS trigger
-- FUNCTION: enforce_external_sync_transaction_integrity() RETURNS trigger
-- FUNCTION: enforce_external_sync_item_integrity() RETURNS trigger
-- FUNCTION: handle_new_user_profile() RETURNS trigger -- SECURITY DEFINER
-- FUNCTION: handle_user_registration_provisioning() RETURNS trigger -- SECURITY DEFINER
-- FUNCTION: set_moodle_token(p_token text) RETURNS void -- SECURITY DEFINER
-- FUNCTION: set_todoist_token(token text) RETURNS TABLE(has_token boolean, updated_at timestamptz) -- SECURITY DEFINER
-- FUNCTION: clear_moodle_token() RETURNS void -- SECURITY DEFINER
-- FUNCTION: rls_auto_enable() RETURNS event_trigger -- SECURITY DEFINER

-- Mobile function
-- FUNCTION: complete_focus_session(p_user_id uuid, p_duration_minutes integer, p_xp integer, p_completed_at timestamptz) RETURNS jsonb -- SECURITY DEFINER; inserts into focus_sessions, completion_events, productivity_daily_stats, streak_snapshots


-- ============================================================================
-- TRIGGER MAPPING SUMMARY
-- ============================================================================
-- tasks:                            BEFORE UPDATE        -> set_updated_at()
-- tasks:                            AFTER UPDATE         -> create_task_completed_notification()
-- workspace_files:                  BEFORE UPDATE        -> set_updated_at()
-- workspace_integrations:           BEFORE UPDATE        -> set_updated_at()
-- workspace_storage_locations:      BEFORE UPDATE        -> set_updated_at()
-- external_sync_transactions:       BEFORE INSERT/UPDATE -> enforce_external_sync_transaction_integrity()
-- external_sync_transaction_items:  BEFORE INSERT/UPDATE -> enforce_external_sync_item_integrity()
-- external_sync_transaction_items:  BEFORE UPDATE        -> set_external_sync_transaction_item_updated_at()
-- notification_preferences:         BEFORE UPDATE        -> set_updated_at()
-- orchestration_runs:               BEFORE UPDATE        -> set_updated_at()
-- productivity_daily_stats:         BEFORE UPDATE        -> set_updated_at()
-- reminder_deliveries:              BEFORE UPDATE        -> set_updated_at()
-- reminder_jobs:                    BEFORE UPDATE        -> set_updated_at()
-- streak_snapshots:                 BEFORE UPDATE        -> set_updated_at()
-- web_push_subscriptions:           BEFORE UPDATE        -> set_updated_at()
-- auth.users:                       AFTER INSERT         -> handle_new_user_profile()
-- auth.users:                       AFTER INSERT         -> handle_user_registration_provisioning()


-- ============================================================================
-- ENTITY RELATIONSHIP DIAGRAM (TEXT)
-- ============================================================================
--
-- auth.users (1) ----< profiles (1)
-- auth.users (1) ----< user_profiles (1)
-- auth.users (1) ----< user_preferences (1)
-- auth.users (1) ----< tasks
-- auth.users (1) ----< primary_tasks
-- auth.users (1) ----< chats
-- auth.users (1) ----< notifications
-- auth.users (1) ----< workspace_members
-- auth.users (1) ----< workspace_invites (invited_user_id)
-- auth.users (1) ----< workspace_invites (consumed_by)
-- auth.users (1) ----< workspaces (created_by)
-- auth.users (1) ----< external_sync_transactions
-- auth.users (1) ----< external_sync_transaction_items
-- auth.users (1) ----< categories
-- auth.users (1) ----< tags
-- auth.users (1) ----< user_badges
-- auth.users (1) ----< focus_sessions
-- auth.users (1) ----< completion_events
-- auth.users (1) ----< productivity_daily_stats
-- auth.users (1) ----< streak_snapshots
-- auth.users (1) ----< calendar_connections
-- auth.users (1) ----< calendar_busy_intervals
-- auth.users (1) ----< fixed_classes
-- auth.users (1) ----< reminder_jobs
-- auth.users (1) ----< reminder_deliveries
-- auth.users (1) ----< notification_preferences
-- auth.users (1) ----< orchestration_runs
-- auth.users (1) ----< managed_schedule_events
-- auth.users (1) ----< web_push_subscriptions
-- auth.users (1) ----< sub_tasks
--
-- workspaces (1) ----< workspace_members
-- workspaces (1) ----< workspace_invites
-- workspaces (1) ----< tasks
-- workspaces (1) ----< chats
-- workspaces (1) ----< workspace_files
-- workspaces (1) ----< workspace_logs
-- workspaces (1) ----< workspace_storage_locations
-- workspaces (1) ----< workspace_integrations
-- workspaces (1) ----< external_sync_transactions
--
-- profiles (1) ----< tasks (assigned_to)
-- profiles (1) ----< messages (user_id)
--
-- categories (1) ----< tasks (category_id)
-- categories (1) ----< primary_tasks (category_id)
--
-- primary_tasks (1) ----< sub_tasks
-- primary_tasks (1) ----< task_tags_map
--
-- badges (1) ----< user_badges
--
-- tags (1) ----< task_tags_map
--
-- tasks (1) ----< task_tags_map
-- tasks (1) ----< external_sync_transaction_items
--
-- external_sync_transactions (1) ----< external_sync_transaction_items
--
-- reminder_jobs (1) ----< reminder_deliveries
--
-- chats (1) ----< messages
