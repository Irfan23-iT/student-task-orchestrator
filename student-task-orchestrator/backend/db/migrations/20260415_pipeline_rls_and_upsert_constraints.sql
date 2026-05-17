ALTER TABLE ingest_pipeline_runs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'ingest_pipeline_runs'
      AND policyname = 'Users can view their own ingest pipeline runs'
  ) THEN
    CREATE POLICY "Users can view their own ingest pipeline runs"
      ON ingest_pipeline_runs
      FOR SELECT
      TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'ingest_pipeline_runs'
      AND policyname = 'Users can insert their own ingest pipeline runs'
  ) THEN
    CREATE POLICY "Users can insert their own ingest pipeline runs"
      ON ingest_pipeline_runs
      FOR INSERT
      TO authenticated
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'ingest_pipeline_runs'
      AND policyname = 'Users can update their own ingest pipeline runs'
  ) THEN
    CREATE POLICY "Users can update their own ingest pipeline runs"
      ON ingest_pipeline_runs
      FOR UPDATE
      TO authenticated
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'primary_tasks_client_ingest_key_key'
      AND conrelid = 'primary_tasks'::regclass
  ) THEN
    ALTER TABLE primary_tasks
      ADD CONSTRAINT primary_tasks_client_ingest_key_key
      UNIQUE (client_ingest_key);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'sub_tasks_client_task_key_key'
      AND conrelid = 'sub_tasks'::regclass
  ) THEN
    ALTER TABLE sub_tasks
      ADD CONSTRAINT sub_tasks_client_task_key_key
      UNIQUE (client_task_key);
  END IF;
END $$;

DROP INDEX IF EXISTS primary_tasks_client_ingest_key_uidx;
DROP INDEX IF EXISTS sub_tasks_client_task_key_uidx;
