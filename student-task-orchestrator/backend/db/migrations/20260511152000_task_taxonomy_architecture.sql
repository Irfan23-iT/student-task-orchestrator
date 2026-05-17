CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS public.categories (
  id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color_hex TEXT NOT NULL DEFAULT '#64748B',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT categories_name_not_blank_chk CHECK (length(trim(name)) > 0),
  CONSTRAINT categories_color_hex_chk CHECK (color_hex ~ '^#[0-9A-Fa-f]{6}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS categories_user_name_unique_idx
  ON public.categories(user_id, lower(name));

CREATE INDEX IF NOT EXISTS categories_user_id_idx
  ON public.categories(user_id);

CREATE TABLE IF NOT EXISTS public.tags (
  id UUID PRIMARY KEY DEFAULT extensions.uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT tags_name_not_blank_chk CHECK (length(trim(name)) > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS tags_user_name_unique_idx
  ON public.tags(user_id, lower(name));

CREATE INDEX IF NOT EXISTS tags_user_id_idx
  ON public.tags(user_id);

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS task_type TEXT NOT NULL DEFAULT 'general',
  ADD COLUMN IF NOT EXISTS category_id UUID,
  ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE public.primary_tasks
  ADD COLUMN IF NOT EXISTS description TEXT,
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS due_date TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS task_type TEXT NOT NULL DEFAULT 'general',
  ADD COLUMN IF NOT EXISTS category_id UUID,
  ADD COLUMN IF NOT EXISTS notes TEXT;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'tasks_status_chk'
      AND conrelid = 'public.tasks'::regclass
  ) THEN
    ALTER TABLE public.tasks DROP CONSTRAINT tasks_status_chk;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'tasks_status_architecture_chk'
      AND conrelid = 'public.tasks'::regclass
  ) THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT tasks_status_architecture_chk
      CHECK (status::text IN ('pending', 'in_progress', 'completed', 'archived', 'Pending', 'In Progress', 'Completed', 'TODO', 'IN_PROGRESS', 'DONE', 'CANCELLED'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'primary_tasks_status_architecture_chk'
      AND conrelid = 'public.primary_tasks'::regclass
  ) THEN
    ALTER TABLE public.primary_tasks
      ADD CONSTRAINT primary_tasks_status_architecture_chk
      CHECK (status::text IN ('pending', 'in_progress', 'completed', 'archived', 'Pending', 'In Progress', 'Completed', 'TODO', 'IN_PROGRESS', 'DONE', 'CANCELLED'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'tasks_task_type_chk'
      AND conrelid = 'public.tasks'::regclass
  ) THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT tasks_task_type_chk
      CHECK (task_type IN ('general', 'exam', 'assignment', 'event', 'reminder'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'primary_tasks_task_type_chk'
      AND conrelid = 'public.primary_tasks'::regclass
  ) THEN
    ALTER TABLE public.primary_tasks
      ADD CONSTRAINT primary_tasks_task_type_chk
      CHECK (task_type IN ('general', 'exam', 'assignment', 'event', 'reminder'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'tasks_category_id_fkey'
      AND conrelid = 'public.tasks'::regclass
  ) THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT tasks_category_id_fkey
      FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'primary_tasks_category_id_fkey'
      AND conrelid = 'public.primary_tasks'::regclass
  ) THEN
    ALTER TABLE public.primary_tasks
      ADD CONSTRAINT primary_tasks_category_id_fkey
      FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS tasks_category_id_idx
  ON public.tasks(category_id);

CREATE INDEX IF NOT EXISTS tasks_status_idx
  ON public.tasks(status);

CREATE INDEX IF NOT EXISTS tasks_task_type_idx
  ON public.tasks(task_type);

CREATE INDEX IF NOT EXISTS primary_tasks_category_id_idx
  ON public.primary_tasks(category_id);

CREATE INDEX IF NOT EXISTS primary_tasks_status_idx
  ON public.primary_tasks(status);

CREATE INDEX IF NOT EXISTS primary_tasks_task_type_idx
  ON public.primary_tasks(task_type);

CREATE TABLE IF NOT EXISTS public.task_tags_map (
  task_id UUID,
  primary_task_id UUID,
  tag_id UUID NOT NULL REFERENCES public.tags(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT task_tags_map_one_task_chk CHECK (
    (task_id IS NOT NULL AND primary_task_id IS NULL)
    OR (task_id IS NULL AND primary_task_id IS NOT NULL)
  )
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'task_tags_map_task_id_fkey'
      AND conrelid = 'public.task_tags_map'::regclass
  ) THEN
    ALTER TABLE public.task_tags_map
      ADD CONSTRAINT task_tags_map_task_id_fkey
      FOREIGN KEY (task_id) REFERENCES public.tasks(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'task_tags_map_primary_task_id_fkey'
      AND conrelid = 'public.task_tags_map'::regclass
  ) THEN
    ALTER TABLE public.task_tags_map
      ADD CONSTRAINT task_tags_map_primary_task_id_fkey
      FOREIGN KEY (primary_task_id) REFERENCES public.primary_tasks(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS task_tags_map_task_tag_unique_idx
  ON public.task_tags_map(task_id, tag_id)
  WHERE task_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS task_tags_map_primary_task_tag_unique_idx
  ON public.task_tags_map(primary_task_id, tag_id)
  WHERE primary_task_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS task_tags_map_tag_id_idx
  ON public.task_tags_map(tag_id);

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_tags_map ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'categories'
      AND policyname = 'Users can manage their own categories'
  ) THEN
    CREATE POLICY "Users can manage their own categories"
      ON public.categories
      FOR ALL
      TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'tags'
      AND policyname = 'Users can manage their own tags'
  ) THEN
    CREATE POLICY "Users can manage their own tags"
      ON public.tags
      FOR ALL
      TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'task_tags_map'
      AND policyname = 'Users can manage tags on their own tasks'
  ) THEN
    CREATE POLICY "Users can manage tags on their own tasks"
      ON public.task_tags_map
      FOR ALL
      TO authenticated
      USING (
        EXISTS (
          SELECT 1
          FROM public.tags
          WHERE public.tags.id = task_tags_map.tag_id
            AND public.tags.user_id = auth.uid()
        )
        AND (
          (
            task_tags_map.task_id IS NOT NULL
            AND EXISTS (
              SELECT 1
              FROM public.tasks
              WHERE public.tasks.id = task_tags_map.task_id
                AND public.tasks.user_id = auth.uid()
            )
          )
          OR (
            task_tags_map.primary_task_id IS NOT NULL
            AND EXISTS (
              SELECT 1
              FROM public.primary_tasks
              WHERE public.primary_tasks.id = task_tags_map.primary_task_id
                AND public.primary_tasks.user_id = auth.uid()
            )
          )
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1
          FROM public.tags
          WHERE public.tags.id = task_tags_map.tag_id
            AND public.tags.user_id = auth.uid()
        )
        AND (
          (
            task_tags_map.task_id IS NOT NULL
            AND EXISTS (
              SELECT 1
              FROM public.tasks
              WHERE public.tasks.id = task_tags_map.task_id
                AND public.tasks.user_id = auth.uid()
            )
          )
          OR (
            task_tags_map.primary_task_id IS NOT NULL
            AND EXISTS (
              SELECT 1
              FROM public.primary_tasks
              WHERE public.primary_tasks.id = task_tags_map.primary_task_id
                AND public.primary_tasks.user_id = auth.uid()
            )
          )
        )
      );
  END IF;
END $$;
