CREATE TABLE IF NOT EXISTS ingest_pipeline_runs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  phase VARCHAR(64) NOT NULL DEFAULT 'IDLE',
  status VARCHAR(32) NOT NULL DEFAULT 'IDLE',
  failed_phase VARCHAR(64),
  last_completed_phase VARCHAR(64),
  primary_task_id UUID REFERENCES primary_tasks(id) ON DELETE SET NULL,
  logical_task_ids JSONB NOT NULL DEFAULT '[]'::JSONB,
  optimizer_payload JSONB,
  schedule_rows JSONB NOT NULL DEFAULT '[]'::JSONB,
  retry_counts JSONB NOT NULL DEFAULT '{}'::JSONB,
  error_message TEXT,
  recoverable BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ingest_pipeline_runs_user_id_updated_at_idx
  ON ingest_pipeline_runs(user_id, updated_at DESC);

ALTER TABLE ingest_pipeline_runs ENABLE ROW LEVEL SECURITY;

ALTER TABLE primary_tasks
  ADD COLUMN IF NOT EXISTS pipeline_run_id UUID REFERENCES ingest_pipeline_runs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS client_ingest_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS primary_tasks_client_ingest_key_uidx
  ON primary_tasks(client_ingest_key)
  WHERE client_ingest_key IS NOT NULL;

ALTER TABLE sub_tasks
  ADD COLUMN IF NOT EXISTS pipeline_run_id UUID REFERENCES ingest_pipeline_runs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS client_task_key TEXT;

CREATE INDEX IF NOT EXISTS sub_tasks_pipeline_run_id_idx
  ON sub_tasks(pipeline_run_id);

CREATE UNIQUE INDEX IF NOT EXISTS sub_tasks_client_task_key_uidx
  ON sub_tasks(client_task_key)
  WHERE client_task_key IS NOT NULL;
