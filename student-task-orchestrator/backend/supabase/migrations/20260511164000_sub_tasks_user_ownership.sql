ALTER TABLE public.sub_tasks
  ADD COLUMN IF NOT EXISTS user_id UUID;

UPDATE public.sub_tasks
SET user_id = public.primary_tasks.user_id
FROM public.primary_tasks
WHERE public.sub_tasks.primary_task_id = public.primary_tasks.id
  AND public.sub_tasks.user_id IS NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'sub_tasks_user_id_fkey'
      AND conrelid = 'public.sub_tasks'::regclass
  ) THEN
    ALTER TABLE public.sub_tasks
      ADD CONSTRAINT sub_tasks_user_id_fkey
      FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS sub_tasks_user_id_idx
  ON public.sub_tasks(user_id);
