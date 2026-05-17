CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS public.tasks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  due_date TIMESTAMP WITH TIME ZONE,
  priority_level TEXT NOT NULL DEFAULT 'Medium',
  status TEXT NOT NULL DEFAULT 'Pending',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT tasks_title_not_blank_chk CHECK (length(trim(title)) > 0),
  CONSTRAINT tasks_priority_level_chk CHECK (priority_level IN ('Low', 'Medium', 'High')),
  CONSTRAINT tasks_status_chk CHECK (status IN ('Pending', 'In Progress', 'Completed'))
);

CREATE INDEX IF NOT EXISTS tasks_user_created_idx
  ON public.tasks(user_id, created_at DESC);

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'tasks'
      AND policyname = 'Users can select their own tasks'
  ) THEN
    CREATE POLICY "Users can select their own tasks"
      ON public.tasks
      FOR SELECT
      TO authenticated
      USING (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'tasks'
      AND policyname = 'Users can insert their own tasks'
  ) THEN
    CREATE POLICY "Users can insert their own tasks"
      ON public.tasks
      FOR INSERT
      TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'tasks'
      AND policyname = 'Users can update their own tasks'
  ) THEN
    CREATE POLICY "Users can update their own tasks"
      ON public.tasks
      FOR UPDATE
      TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'tasks'
      AND policyname = 'Users can delete their own tasks'
  ) THEN
    CREATE POLICY "Users can delete their own tasks"
      ON public.tasks
      FOR DELETE
      TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;
