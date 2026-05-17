CREATE TABLE IF NOT EXISTS public.user_profiles (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    wake_time TIME NOT NULL DEFAULT TIME '05:00',
    sleep_time TIME NOT NULL DEFAULT TIME '23:00',
    breakfast_start TIME NOT NULL DEFAULT TIME '07:30',
    breakfast_end TIME NOT NULL DEFAULT TIME '08:30',
    lunch_start TIME NOT NULL DEFAULT TIME '12:30',
    lunch_end TIME NOT NULL DEFAULT TIME '13:30',
    dinner_start TIME NOT NULL DEFAULT TIME '19:00',
    dinner_end TIME NOT NULL DEFAULT TIME '20:00',
    transit_buffer_minutes INTEGER NOT NULL DEFAULT 30,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    CONSTRAINT user_profiles_day_bounds_chk CHECK (wake_time < sleep_time),
    CONSTRAINT user_profiles_breakfast_window_chk CHECK (breakfast_start < breakfast_end),
    CONSTRAINT user_profiles_lunch_window_chk CHECK (lunch_start < lunch_end),
    CONSTRAINT user_profiles_dinner_window_chk CHECK (dinner_start < dinner_end),
    CONSTRAINT user_profiles_transit_buffer_chk CHECK (transit_buffer_minutes BETWEEN 0 AND 180)
);

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_profiles'
          AND policyname = 'Users can view their own schedule preferences'
    ) THEN
        CREATE POLICY "Users can view their own schedule preferences"
        ON public.user_profiles
        FOR SELECT
        USING (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_profiles'
          AND policyname = 'Users can insert their own schedule preferences'
    ) THEN
        CREATE POLICY "Users can insert their own schedule preferences"
        ON public.user_profiles
        FOR INSERT
        WITH CHECK (auth.uid() = user_id);
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'user_profiles'
          AND policyname = 'Users can update their own schedule preferences'
    ) THEN
        CREATE POLICY "Users can update their own schedule preferences"
        ON public.user_profiles
        FOR UPDATE
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
    END IF;
END $$;

INSERT INTO public.user_profiles (user_id)
SELECT public.users.id
FROM public.users
ON CONFLICT (user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_user_profiles_updated_at ON public.user_profiles;

CREATE TRIGGER set_user_profiles_updated_at
BEFORE UPDATE ON public.user_profiles
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name)
  VALUES (new.id, new.email, new.raw_user_meta_data->>'full_name')
  ON CONFLICT (id) DO UPDATE
  SET email = EXCLUDED.email,
      full_name = COALESCE(EXCLUDED.full_name, public.users.full_name);

  INSERT INTO public.user_profiles (user_id)
  VALUES (new.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
