CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    full_name VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.primary_tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    due_date TIMESTAMP WITH TIME ZONE,
    pipeline_run_id UUID,
    client_ingest_key TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.ingest_pipeline_runs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    phase VARCHAR(64) NOT NULL DEFAULT 'IDLE',
    status VARCHAR(32) NOT NULL DEFAULT 'IDLE',
    failed_phase VARCHAR(64),
    last_completed_phase VARCHAR(64),
    primary_task_id UUID REFERENCES public.primary_tasks(id) ON DELETE SET NULL,
    logical_task_ids JSONB NOT NULL DEFAULT '[]'::JSONB,
    optimizer_payload JSONB,
    schedule_rows JSONB NOT NULL DEFAULT '[]'::JSONB,
    retry_counts JSONB NOT NULL DEFAULT '{}'::JSONB,
    error_message TEXT,
    recoverable BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'primary_tasks_pipeline_run_id_fkey'
          AND conrelid = 'public.primary_tasks'::regclass
    ) THEN
        ALTER TABLE public.primary_tasks
            ADD CONSTRAINT primary_tasks_pipeline_run_id_fkey
            FOREIGN KEY (pipeline_run_id) REFERENCES public.ingest_pipeline_runs(id) ON DELETE SET NULL;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.sub_tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    primary_task_id UUID NOT NULL REFERENCES public.primary_tasks(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'pending',
    estimated_minutes INTEGER,
    priority VARCHAR(50) NOT NULL DEFAULT 'low',
    due_date TIMESTAMP WITH TIME ZONE,
    ai_steps JSONB NOT NULL DEFAULT '[]'::JSONB,
    scheduled_date DATE,
    scheduled_start_time TIME,
    scheduled_end_time TIME,
    is_chunked BOOLEAN NOT NULL DEFAULT FALSE,
    pipeline_run_id UUID REFERENCES public.ingest_pipeline_runs(id) ON DELETE SET NULL,
    client_task_key TEXT,
    parent_task_id UUID REFERENCES public.sub_tasks(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT sub_tasks_schedule_window_chk CHECK (
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
    )
);

CREATE INDEX IF NOT EXISTS primary_tasks_user_id_idx ON public.primary_tasks(user_id);
CREATE INDEX IF NOT EXISTS ingest_pipeline_runs_user_id_updated_at_idx ON public.ingest_pipeline_runs(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS sub_tasks_primary_task_id_idx ON public.sub_tasks(primary_task_id);
CREATE INDEX IF NOT EXISTS sub_tasks_scheduled_date_idx ON public.sub_tasks(scheduled_date);
CREATE INDEX IF NOT EXISTS sub_tasks_parent_task_id_idx ON public.sub_tasks(parent_task_id);
CREATE INDEX IF NOT EXISTS sub_tasks_pipeline_run_id_idx ON public.sub_tasks(pipeline_run_id);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'primary_tasks_client_ingest_key_key'
          AND conrelid = 'public.primary_tasks'::regclass
    ) THEN
        ALTER TABLE public.primary_tasks
            ADD CONSTRAINT primary_tasks_client_ingest_key_key UNIQUE (client_ingest_key);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'sub_tasks_client_task_key_key'
          AND conrelid = 'public.sub_tasks'::regclass
    ) THEN
        ALTER TABLE public.sub_tasks
            ADD CONSTRAINT sub_tasks_client_task_key_key UNIQUE (client_task_key);
    END IF;
END $$;

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.primary_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ingest_pipeline_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sub_tasks ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'users'
          AND policyname = 'Users can view their own profile'
    ) THEN
        CREATE POLICY "Users can view their own profile"
        ON public.users
        FOR SELECT
        TO authenticated
        USING (auth.uid() = id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'users'
          AND policyname = 'Users can update their own profile'
    ) THEN
        CREATE POLICY "Users can update their own profile"
        ON public.users
        FOR UPDATE
        TO authenticated
        USING (auth.uid() = id)
        WITH CHECK (auth.uid() = id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'primary_tasks'
          AND policyname = 'Users can manage their own primary tasks'
    ) THEN
        CREATE POLICY "Users can manage their own primary tasks"
        ON public.primary_tasks
        FOR ALL
        TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'ingest_pipeline_runs'
          AND policyname = 'Users can view their own ingest pipeline runs'
    ) THEN
        CREATE POLICY "Users can view their own ingest pipeline runs"
        ON public.ingest_pipeline_runs
        FOR SELECT
        TO authenticated
        USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'ingest_pipeline_runs'
          AND policyname = 'Users can insert their own ingest pipeline runs'
    ) THEN
        CREATE POLICY "Users can insert their own ingest pipeline runs"
        ON public.ingest_pipeline_runs
        FOR INSERT
        TO authenticated
        WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'ingest_pipeline_runs'
          AND policyname = 'Users can update their own ingest pipeline runs'
    ) THEN
        CREATE POLICY "Users can update their own ingest pipeline runs"
        ON public.ingest_pipeline_runs
        FOR UPDATE
        TO authenticated
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'sub_tasks'
          AND policyname = 'Users can manage their own sub-tasks'
    ) THEN
        CREATE POLICY "Users can manage their own sub-tasks"
        ON public.sub_tasks
        FOR ALL
        TO authenticated
        USING (
            EXISTS (
                SELECT 1
                FROM public.primary_tasks
                WHERE public.primary_tasks.id = public.sub_tasks.primary_task_id
                  AND public.primary_tasks.user_id = auth.uid()
            )
        )
        WITH CHECK (
            EXISTS (
                SELECT 1
                FROM public.primary_tasks
                WHERE public.primary_tasks.id = public.sub_tasks.primary_task_id
                  AND public.primary_tasks.user_id = auth.uid()
            )
        );
    END IF;
END $$;

INSERT INTO public.users (id, email, full_name, created_at)
SELECT
    au.id,
    au.email,
    au.raw_user_meta_data->>'full_name',
    COALESCE(au.created_at, NOW())
FROM auth.users AS au
WHERE au.email IS NOT NULL
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    full_name = COALESCE(EXCLUDED.full_name, public.users.full_name);

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
    INSERT INTO public.users (id, email, full_name, created_at)
    VALUES (NEW.id, NEW.email, NEW.raw_user_meta_data->>'full_name', COALESCE(NEW.created_at, NOW()))
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        full_name = COALESCE(EXCLUDED.full_name, public.users.full_name);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();
