-- Relational schema for Intelligent Student Task & Focus Orchestrator

-- Users Table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    full_name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- User Profiles Table
CREATE TABLE user_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    wake_time TIME NOT NULL DEFAULT TIME '05:00',
    sleep_time TIME NOT NULL DEFAULT TIME '23:00',
    breakfast_start TIME NOT NULL DEFAULT TIME '07:30',
    breakfast_end TIME NOT NULL DEFAULT TIME '08:30',
    lunch_start TIME NOT NULL DEFAULT TIME '12:30',
    lunch_end TIME NOT NULL DEFAULT TIME '13:30',
    dinner_start TIME NOT NULL DEFAULT TIME '19:00',
    dinner_end TIME NOT NULL DEFAULT TIME '20:00',
    transit_buffer_minutes INTEGER NOT NULL DEFAULT 30,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT user_profiles_day_bounds_chk CHECK (wake_time < sleep_time),
    CONSTRAINT user_profiles_breakfast_window_chk CHECK (breakfast_start < breakfast_end),
    CONSTRAINT user_profiles_lunch_window_chk CHECK (lunch_start < lunch_end),
    CONSTRAINT user_profiles_dinner_window_chk CHECK (dinner_start < dinner_end),
    CONSTRAINT user_profiles_transit_buffer_chk CHECK (transit_buffer_minutes BETWEEN 0 AND 180)
);

-- Primary Tasks Table
CREATE TABLE primary_tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    due_date TIMESTAMP WITH TIME ZONE,
    pipeline_run_id UUID,
    client_ingest_key TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Ingest Pipeline Runs Table
CREATE TABLE ingest_pipeline_runs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    phase VARCHAR(64) NOT NULL DEFAULT 'IDLE',
    status VARCHAR(32) NOT NULL DEFAULT 'IDLE',
    failed_phase VARCHAR(64),
    last_completed_phase VARCHAR(64),
    primary_task_id UUID REFERENCES primary_tasks(id) ON DELETE SET NULL,
    logical_task_ids JSONB NOT NULL DEFAULT '[]'::JSONB,
    optimizer_payload JSONB,
    schedule_rows JSONB NOT NULL DEFAULT '[]'::JSONB,
    retry_counts JSONB NOT NULL DEFAULT '{}'::JSONB,
    error_message TEXT,
    recoverable BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE primary_tasks
    ADD CONSTRAINT primary_tasks_pipeline_run_id_fkey
    FOREIGN KEY (pipeline_run_id) REFERENCES ingest_pipeline_runs(id) ON DELETE SET NULL;

-- Sub Tasks Table
CREATE TABLE sub_tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    primary_task_id UUID NOT NULL REFERENCES primary_tasks(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'pending',
    estimated_minutes INTEGER,
    priority VARCHAR(50) DEFAULT 'low',
    due_date TIMESTAMP WITH TIME ZONE,
    ai_steps JSONB NOT NULL DEFAULT '[]'::JSONB,
    scheduled_date DATE,
    scheduled_start_time TIME,
    scheduled_end_time TIME,
    is_chunked BOOLEAN NOT NULL DEFAULT FALSE,
    pipeline_run_id UUID REFERENCES ingest_pipeline_runs(id) ON DELETE SET NULL,
    client_task_key TEXT,
    parent_task_id UUID REFERENCES sub_tasks(id) ON DELETE CASCADE,
    CONSTRAINT sub_tasks_schedule_window_chk
        CHECK (
            (
                scheduled_date IS NULL
                AND scheduled_start_time IS NULL
                AND scheduled_end_time IS NULL
            )
            OR (
                scheduled_date IS NOT NULL
                AND scheduled_start_time IS NOT NULL
                AND scheduled_end_time IS NOT NULL
                AND scheduled_start_time < scheduled_end_time
            )
        ),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create simple indexes for fast lookup (Supabase / Postgres best practices)
CREATE INDEX IF NOT EXISTS primary_tasks_user_id_idx ON primary_tasks(user_id);
CREATE INDEX IF NOT EXISTS ingest_pipeline_runs_user_id_updated_at_idx ON ingest_pipeline_runs(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS sub_tasks_primary_task_id_idx ON sub_tasks(primary_task_id);
CREATE INDEX IF NOT EXISTS sub_tasks_scheduled_date_idx ON sub_tasks(scheduled_date);
CREATE INDEX IF NOT EXISTS sub_tasks_parent_task_id_idx ON sub_tasks(parent_task_id);
CREATE INDEX IF NOT EXISTS sub_tasks_pipeline_run_id_idx ON sub_tasks(pipeline_run_id);
ALTER TABLE primary_tasks
    ADD CONSTRAINT primary_tasks_client_ingest_key_key UNIQUE (client_ingest_key);
ALTER TABLE sub_tasks
    ADD CONSTRAINT sub_tasks_client_task_key_key UNIQUE (client_task_key);

-- Enable Row-Level Security (RLS) on tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE primary_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE ingest_pipeline_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE sub_tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own ingest pipeline runs"
ON ingest_pipeline_runs FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own ingest pipeline runs"
ON ingest_pipeline_runs FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own ingest pipeline runs"
ON ingest_pipeline_runs FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION persist_weekly_schedule(
    p_schedule_rows JSONB,
    p_logical_task_ids JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
    schedule_entry JSONB;
    affected_task_ids_from_schedule UUID[];
    affected_task_ids_from_payload UUID[];
    affected_task_ids UUID[];
    inserted_chunk_count INTEGER := 0;
BEGIN
    IF p_schedule_rows IS NULL OR jsonb_typeof(p_schedule_rows) <> 'array' THEN
        RAISE EXCEPTION 'persist_weekly_schedule expects a JSON array payload';
    END IF;

    IF p_logical_task_ids IS NULL OR jsonb_typeof(p_logical_task_ids) <> 'array' THEN
        RAISE EXCEPTION 'persist_weekly_schedule expects logical task ids as a JSON array payload';
    END IF;

    SELECT COALESCE(array_agg(DISTINCT (value->>'source_task_id')::UUID), '{}')
    INTO affected_task_ids_from_schedule
    FROM jsonb_array_elements(p_schedule_rows)
    WHERE value ? 'source_task_id'
      AND NULLIF(value->>'source_task_id', '') IS NOT NULL;

    SELECT COALESCE(array_agg(DISTINCT value::UUID), '{}')
    INTO affected_task_ids_from_payload
    FROM jsonb_array_elements_text(p_logical_task_ids)
    WHERE NULLIF(value, '') IS NOT NULL;

    SELECT ARRAY(
        SELECT DISTINCT task_id
        FROM unnest(
            COALESCE(affected_task_ids_from_schedule, '{}'::UUID[])
            || COALESCE(affected_task_ids_from_payload, '{}'::UUID[])
        ) AS task_id
        WHERE task_id IS NOT NULL
    )
    INTO affected_task_ids;

    IF COALESCE(array_length(affected_task_ids, 1), 0) = 0 THEN
        RETURN jsonb_build_object(
            'affected_task_count', 0,
            'inserted_chunk_count', 0
        );
    END IF;

    DELETE FROM sub_tasks
    WHERE parent_task_id = ANY(affected_task_ids);

    UPDATE sub_tasks
    SET scheduled_date = NULL,
        scheduled_start_time = NULL,
        scheduled_end_time = NULL,
        is_chunked = FALSE
    WHERE id = ANY(affected_task_ids);

    FOR schedule_entry IN
        SELECT value
        FROM jsonb_array_elements(p_schedule_rows)
    LOOP
        IF COALESCE((schedule_entry->>'is_chunked')::BOOLEAN, FALSE) THEN
            UPDATE sub_tasks
            SET is_chunked = TRUE,
                scheduled_date = NULL,
                scheduled_start_time = NULL,
                scheduled_end_time = NULL
            WHERE id = (schedule_entry->>'source_task_id')::UUID;

            IF NULLIF(schedule_entry->>'scheduled_date', '') IS NOT NULL
               AND NULLIF(schedule_entry->>'scheduled_start_time', '') IS NOT NULL
               AND NULLIF(schedule_entry->>'scheduled_end_time', '') IS NOT NULL THEN
                INSERT INTO sub_tasks (
                    primary_task_id,
                    title,
                    status,
                    estimated_minutes,
                    priority,
                    due_date,
                    ai_steps,
                    scheduled_date,
                    scheduled_start_time,
                    scheduled_end_time,
                    is_chunked,
                    parent_task_id
                )
                SELECT
                    primary_task_id,
                    COALESCE(NULLIF(schedule_entry->>'title', ''), title),
                    status,
                    COALESCE(
                        NULLIF(schedule_entry->>'estimated_minutes', '')::INTEGER,
                        estimated_minutes
                    ),
                    priority,
                    due_date,
                    ai_steps,
                    (schedule_entry->>'scheduled_date')::DATE,
                    (schedule_entry->>'scheduled_start_time')::TIME,
                    (schedule_entry->>'scheduled_end_time')::TIME,
                    TRUE,
                    id
                FROM sub_tasks
                WHERE id = (schedule_entry->>'source_task_id')::UUID;

                inserted_chunk_count := inserted_chunk_count + 1;
            END IF;
        ELSE
            UPDATE sub_tasks
            SET scheduled_date = (schedule_entry->>'scheduled_date')::DATE,
                scheduled_start_time = (schedule_entry->>'scheduled_start_time')::TIME,
                scheduled_end_time = (schedule_entry->>'scheduled_end_time')::TIME,
                is_chunked = FALSE,
                parent_task_id = NULL
            WHERE id = (schedule_entry->>'source_task_id')::UUID;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'affected_task_count', COALESCE(array_length(affected_task_ids, 1), 0),
        'inserted_chunk_count', inserted_chunk_count
    );
END;
$$;
