ALTER TABLE sub_tasks
  ADD COLUMN IF NOT EXISTS priority VARCHAR(50) DEFAULT 'low',
  ADD COLUMN IF NOT EXISTS due_date TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS ai_steps JSONB NOT NULL DEFAULT '[]'::JSONB,
  ADD COLUMN IF NOT EXISTS scheduled_date DATE,
  ADD COLUMN IF NOT EXISTS scheduled_start_time TIME,
  ADD COLUMN IF NOT EXISTS scheduled_end_time TIME,
  ADD COLUMN IF NOT EXISTS is_chunked BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS parent_task_id UUID REFERENCES sub_tasks(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS sub_tasks_scheduled_date_idx
  ON sub_tasks(scheduled_date);

CREATE INDEX IF NOT EXISTS sub_tasks_parent_task_id_idx
  ON sub_tasks(parent_task_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'sub_tasks_schedule_window_chk'
      AND conrelid = 'sub_tasks'::regclass
  ) THEN
    ALTER TABLE sub_tasks
      ADD CONSTRAINT sub_tasks_schedule_window_chk
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
      );
  END IF;
END $$;

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
