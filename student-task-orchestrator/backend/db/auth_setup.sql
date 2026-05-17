-- 1. Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE primary_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE ingest_pipeline_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE sub_tasks ENABLE ROW LEVEL SECURITY;

-- 2. Create Policies for 'users' table
CREATE POLICY "Users can view their own profile" 
ON users FOR SELECT 
USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile" 
ON users FOR UPDATE 
USING (auth.uid() = id);

CREATE POLICY "Users can view their own schedule preferences"
ON user_profiles FOR SELECT
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own schedule preferences"
ON user_profiles FOR INSERT
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own schedule preferences"
ON user_profiles FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 3. Create Policies for 'primary_tasks' table
CREATE POLICY "Users can manage their own primary tasks" 
ON primary_tasks FOR ALL 
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own ingest pipeline runs"
ON ingest_pipeline_runs FOR SELECT
TO authenticated
USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own ingest pipeline runs"
ON ingest_pipeline_runs FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own ingest pipeline runs"
ON ingest_pipeline_runs FOR UPDATE
TO authenticated
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 4. Create Policies for 'sub_tasks' table (via primary_tasks relationship)
CREATE POLICY "Users can manage their own sub-tasks" 
ON sub_tasks FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM primary_tasks 
    WHERE primary_tasks.id = sub_tasks.primary_task_id 
    AND primary_tasks.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM primary_tasks 
    WHERE primary_tasks.id = sub_tasks.primary_task_id 
    AND primary_tasks.user_id = auth.uid()
  )
);

-- 5. Trigger to automatically create a user record in 'public.users' on signup
-- This ensures our internal 'users' table stays in sync with Supabase Auth
CREATE OR REPLACE FUNCTION public.handle_new_user() 
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name)
  VALUES (new.id, new.email, new.raw_user_meta_data->>'full_name');
  INSERT INTO public.user_profiles (user_id)
  VALUES (new.id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
