import { supabase } from '../config/supabase.js';

const sanitizePipelineRow = (userId, row = {}) => ({
  id: row.id || null,
  user_id: userId,
  phase: row.phase || 'IDLE',
  status: row.status || 'IDLE',
  failed_phase: row.failed_phase || null,
  last_completed_phase: row.last_completed_phase || 'IDLE',
  primary_task_id: row.primary_task_id || null,
  logical_task_ids: Array.isArray(row.logical_task_ids) ? row.logical_task_ids : [],
  optimizer_payload: row.optimizer_payload && typeof row.optimizer_payload === 'object' ? row.optimizer_payload : null,
  schedule_rows: Array.isArray(row.schedule_rows) ? row.schedule_rows : [],
  retry_counts: row.retry_counts && typeof row.retry_counts === 'object' ? row.retry_counts : {},
  error_message: row.error_message || null,
  recoverable: Boolean(row.recoverable),
  updated_at: row.updated_at || new Date().toISOString()
});

export const upsertPipelineState = async (req, res) => {
  try {
    const payload = sanitizePipelineRow(req.user.id, req.body || {});
    if (!payload.id) {
      return res.status(400).json({
        error: 'Pipeline id is required.'
      });
    }

    const { data: existingPipelineRun, error: existingPipelineRunError } = await supabase
      .from('ingest_pipeline_runs')
      .select('id, user_id')
      .eq('id', payload.id)
      .maybeSingle();

    if (existingPipelineRunError) throw existingPipelineRunError;
    if (existingPipelineRun?.user_id && existingPipelineRun.user_id !== req.user.id) {
      return res.status(403).json({
        error: 'Pipeline run access denied.'
      });
    }

    const { data, error } = await supabase
      .from('ingest_pipeline_runs')
      .upsert(payload, { onConflict: 'id' })
      .select('*')
      .single();

    if (error) throw error;

    res.status(200).json({
      storageMode: 'remote',
      pipelineRun: data
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to persist pipeline state',
      details: error.message
    });
  }
};

export const getLatestPipelineState = async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('ingest_pipeline_runs')
      .select('*')
      .eq('user_id', req.user.id)
      .neq('status', 'SUCCESS')
      .order('updated_at', { ascending: false })
      .limit(1);

    if (error) throw error;

    res.status(200).json({
      storageMode: 'remote',
      pipelineRun: Array.isArray(data) ? (data[0] || null) : null
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to load latest pipeline state',
      details: error.message
    });
  }
};
