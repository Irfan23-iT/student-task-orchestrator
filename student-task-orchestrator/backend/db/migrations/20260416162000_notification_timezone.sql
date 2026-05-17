ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS time_zone TEXT NOT NULL DEFAULT 'UTC';
