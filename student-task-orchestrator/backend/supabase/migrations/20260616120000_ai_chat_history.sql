CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS public.ai_chats (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT 'New Chat',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ai_chats_user_updated_idx
  ON public.ai_chats(user_id, updated_at DESC);

ALTER TABLE public.ai_chats ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'ai_chats' AND policyname = 'Users can manage their own ai chats'
  ) THEN
    CREATE POLICY "Users can manage their own ai chats"
      ON public.ai_chats
      FOR ALL
      TO authenticated
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

DROP TRIGGER IF EXISTS set_ai_chats_updated_at ON public.ai_chats;
CREATE TRIGGER set_ai_chats_updated_at
  BEFORE UPDATE ON public.ai_chats
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.ai_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  chat_id UUID NOT NULL REFERENCES public.ai_chats(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  action_type TEXT,
  action_performed BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  CONSTRAINT ai_messages_role_chk CHECK (role IN ('user', 'assistant'))
);

CREATE INDEX IF NOT EXISTS ai_messages_chat_created_idx
  ON public.ai_messages(chat_id, created_at ASC);

CREATE INDEX IF NOT EXISTS ai_messages_user_idx
  ON public.ai_messages(user_id, created_at DESC);

ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'ai_messages' AND policyname = 'Users can manage their own ai messages'
  ) THEN
    CREATE POLICY "Users can manage their own ai messages"
      ON public.ai_messages
      FOR ALL
      TO authenticated
      USING (auth.uid() = user_id)
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;
