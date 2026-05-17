CREATE UNIQUE INDEX IF NOT EXISTS reminder_deliveries_job_channel_uidx
  ON public.reminder_deliveries(reminder_job_id, channel);
