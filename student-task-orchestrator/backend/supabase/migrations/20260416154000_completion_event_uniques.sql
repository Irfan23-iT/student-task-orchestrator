CREATE UNIQUE INDEX IF NOT EXISTS completion_events_user_task_uidx
  ON public.completion_events(user_id, sub_task_id)
  WHERE sub_task_id IS NOT NULL;
