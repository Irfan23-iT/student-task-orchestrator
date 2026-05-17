CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS access_disabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS access_banned BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS access_revoked_after TIMESTAMP WITH TIME ZONE;

CREATE TABLE IF NOT EXISTS public.fixed_classes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  day_of_week VARCHAR(3) NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  class_name TEXT NOT NULL,
  class_type VARCHAR(16) NOT NULL DEFAULT 'Lect',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT fixed_classes_day_chk CHECK (day_of_week IN ('MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN')),
  CONSTRAINT fixed_classes_time_chk CHECK (start_time < end_time)
);

CREATE INDEX IF NOT EXISTS fixed_classes_user_day_idx
  ON public.fixed_classes(user_id, day_of_week, start_time);

ALTER TABLE public.fixed_classes ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'fixed_classes'
      AND policyname = 'Users can manage their own fixed classes'
  ) THEN
    CREATE POLICY "Users can manage their own fixed classes"
      ON public.fixed_classes
      FOR ALL
      TO authenticated
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DROP TRIGGER IF EXISTS set_fixed_classes_updated_at ON public.fixed_classes;

CREATE TRIGGER set_fixed_classes_updated_at
BEFORE UPDATE ON public.fixed_classes
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.sub_tasks
  ADD COLUMN IF NOT EXISTS user_id UUID,
  ADD COLUMN IF NOT EXISTS priority_score DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS priority_band VARCHAR(32),
  ADD COLUMN IF NOT EXISTS priority_reason TEXT,
  ADD COLUMN IF NOT EXISTS manual_priority_override BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE public.sub_tasks AS sub
SET user_id = parent.user_id
FROM public.primary_tasks AS parent
WHERE sub.primary_task_id = parent.id
  AND sub.user_id IS NULL;

CREATE INDEX IF NOT EXISTS sub_tasks_user_id_created_at_idx
  ON public.sub_tasks(user_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.sync_sub_task_user_id()
RETURNS trigger AS $$
BEGIN
  IF NEW.primary_task_id IS NOT NULL THEN
    SELECT user_id
    INTO NEW.user_id
    FROM public.primary_tasks
    WHERE id = NEW.primary_task_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sync_sub_task_user_id_before_write ON public.sub_tasks;

CREATE TRIGGER sync_sub_task_user_id_before_write
BEFORE INSERT OR UPDATE OF primary_task_id
ON public.sub_tasks
FOR EACH ROW
EXECUTE FUNCTION public.sync_sub_task_user_id();

CREATE TABLE IF NOT EXISTS public.orchestration_runs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  status TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 1,
  idempotency_key TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  request_id TEXT,
  source_surface TEXT NOT NULL DEFAULT 'dashboard',
  payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  result_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  warning_summary JSONB NOT NULL DEFAULT '{}'::JSONB,
  error_message TEXT,
  queued_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  started_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  lease_owner TEXT,
  lease_expires_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT orchestration_runs_status_chk CHECK (
    status IN ('QUEUED', 'PROCESSING', 'COMPLETED', 'COMPLETED_WITH_WARNINGS', 'FAILED', 'FAILED_TIMEOUT', 'CANCELLED')
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS orchestration_runs_user_idempotency_uidx
  ON public.orchestration_runs(user_id, idempotency_key);

CREATE INDEX IF NOT EXISTS orchestration_runs_user_updated_idx
  ON public.orchestration_runs(user_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS orchestration_runs_status_lease_idx
  ON public.orchestration_runs(status, lease_expires_at);

ALTER TABLE public.orchestration_runs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'orchestration_runs'
      AND policyname = 'Users can manage their own orchestration runs'
  ) THEN
    CREATE POLICY "Users can manage their own orchestration runs"
      ON public.orchestration_runs
      FOR ALL
      TO authenticated
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DROP TRIGGER IF EXISTS set_orchestration_runs_updated_at ON public.orchestration_runs;

CREATE TRIGGER set_orchestration_runs_updated_at
BEFORE UPDATE ON public.orchestration_runs
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.orchestration_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  run_id UUID NOT NULL REFERENCES public.orchestration_runs(id) ON DELETE CASCADE,
  attempt_count INTEGER NOT NULL DEFAULT 1,
  event_type TEXT NOT NULL,
  status TEXT NOT NULL,
  agent TEXT,
  message TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS orchestration_events_user_run_created_idx
  ON public.orchestration_events(user_id, run_id, created_at ASC);

CREATE UNIQUE INDEX IF NOT EXISTS orchestration_events_timeout_once_uidx
  ON public.orchestration_events(run_id, attempt_count)
  WHERE event_type = 'RUN_TIMEOUT_TERMINAL';

ALTER TABLE public.orchestration_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'orchestration_events'
      AND policyname = 'Users can view their own orchestration events'
  ) THEN
    CREATE POLICY "Users can view their own orchestration events"
      ON public.orchestration_events
      FOR SELECT
      TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.orchestration_chunk_results (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  run_id UUID NOT NULL REFERENCES public.orchestration_runs(id) ON DELETE CASCADE,
  chunk_index INTEGER NOT NULL,
  page_start INTEGER,
  page_end INTEGER,
  status TEXT NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 1,
  warning_code TEXT,
  error_message TEXT,
  extracted_item_count INTEGER NOT NULL DEFAULT 0,
  raw_excerpt_hash TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT orchestration_chunk_results_chunk_idx_chk CHECK (chunk_index >= 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS orchestration_chunk_results_run_chunk_uidx
  ON public.orchestration_chunk_results(run_id, chunk_index);

CREATE INDEX IF NOT EXISTS orchestration_chunk_results_user_run_idx
  ON public.orchestration_chunk_results(user_id, run_id, chunk_index);

ALTER TABLE public.orchestration_chunk_results ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'orchestration_chunk_results'
      AND policyname = 'Users can view their own orchestration chunk results'
  ) THEN
    CREATE POLICY "Users can view their own orchestration chunk results"
      ON public.orchestration_chunk_results
      FOR SELECT
      TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END $$;

DROP TRIGGER IF EXISTS set_orchestration_chunk_results_updated_at ON public.orchestration_chunk_results;

CREATE TRIGGER set_orchestration_chunk_results_updated_at
BEFORE UPDATE ON public.orchestration_chunk_results
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.claim_timed_out_orchestration_runs(p_limit INTEGER DEFAULT 20)
RETURNS TABLE (
  run_id UUID,
  user_id UUID,
  attempt_count INTEGER,
  kind TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
  target_run RECORD;
BEGIN
  FOR target_run IN
    SELECT id, user_id, attempt_count, kind
    FROM public.orchestration_runs
    WHERE status IN ('QUEUED', 'PROCESSING')
      AND lease_expires_at IS NOT NULL
      AND lease_expires_at <= NOW()
    ORDER BY lease_expires_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT GREATEST(COALESCE(p_limit, 20), 1)
  LOOP
    UPDATE public.orchestration_runs
    SET status = 'FAILED_TIMEOUT',
        error_message = 'Run timed out before the worker renewed its lease.',
        completed_at = NOW(),
        lease_owner = NULL,
        lease_expires_at = NULL,
        updated_at = NOW()
    WHERE id = target_run.id;

    BEGIN
      INSERT INTO public.orchestration_events (
        user_id,
        run_id,
        attempt_count,
        event_type,
        status,
        agent,
        message,
        payload
      )
      VALUES (
        target_run.user_id,
        target_run.id,
        target_run.attempt_count,
        'RUN_TIMEOUT_TERMINAL',
        'FAILED_TIMEOUT',
        'sweeper',
        'Run timed out and was failed by the supervisor sweeper.',
        jsonb_build_object('kind', target_run.kind)
      );
    EXCEPTION
      WHEN unique_violation THEN
        NULL;
    END;

    run_id := target_run.id;
    user_id := target_run.user_id;
    attempt_count := target_run.attempt_count;
    kind := target_run.kind;
    RETURN NEXT;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.persist_weekly_schedule(
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
    RETURN jsonb_build_object('affected_task_count', 0, 'inserted_chunk_count', 0);
  END IF;

  DELETE FROM public.sub_tasks
  WHERE parent_task_id = ANY(affected_task_ids);

  UPDATE public.sub_tasks
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
      UPDATE public.sub_tasks
      SET is_chunked = TRUE,
          scheduled_date = NULL,
          scheduled_start_time = NULL,
          scheduled_end_time = NULL
      WHERE id = (schedule_entry->>'source_task_id')::UUID;

      IF NULLIF(schedule_entry->>'scheduled_date', '') IS NOT NULL
         AND NULLIF(schedule_entry->>'scheduled_start_time', '') IS NOT NULL
         AND NULLIF(schedule_entry->>'scheduled_end_time', '') IS NOT NULL THEN
        INSERT INTO public.sub_tasks (
          user_id,
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
          parent_task_id,
          pipeline_run_id,
          priority_score,
          priority_band,
          priority_reason,
          manual_priority_override
        )
        SELECT
          user_id,
          primary_task_id,
          COALESCE(NULLIF(schedule_entry->>'title', ''), title),
          status,
          COALESCE(NULLIF(schedule_entry->>'estimated_minutes', '')::INTEGER, estimated_minutes),
          priority,
          due_date,
          ai_steps,
          (schedule_entry->>'scheduled_date')::DATE,
          (schedule_entry->>'scheduled_start_time')::TIME,
          (schedule_entry->>'scheduled_end_time')::TIME,
          TRUE,
          id,
          pipeline_run_id,
          priority_score,
          priority_band,
          priority_reason,
          manual_priority_override
        FROM public.sub_tasks
        WHERE id = (schedule_entry->>'source_task_id')::UUID;

        inserted_chunk_count := inserted_chunk_count + 1;
      END IF;
    ELSE
      UPDATE public.sub_tasks
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
