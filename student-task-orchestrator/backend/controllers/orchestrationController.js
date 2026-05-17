import { supabase } from '../config/supabase.js';
import { sha256 } from '../lib/hash.js';
import {
  acquireIdempotencyLock,
  finalizeAcceptedLock,
  startPendingHeartbeat
} from '../lib/idempotency.js';
import { log } from '../lib/logger.js';
import { publishStreamJob } from '../lib/queue.js';
import {
  isTerminalRunStatus,
  RUN_KINDS,
  RUN_STATUSES,
  STREAMS_BY_KIND
} from '../lib/runStatus.js';
import { getRedis } from '../lib/redis.js';

const ALLOWED_KINDS = new Set(Object.values(RUN_KINDS));
const MAX_JSON_PAYLOAD_BYTES = 16 * 1024 * 1024;
const MAX_ASSIGNMENT_TEXT_LENGTH = 250_000;
const MAX_IMAGE_DATA_URL_LENGTH = 15 * 1024 * 1024;
const MAX_DOCUMENT_BYTES = 15 * 1024 * 1024;

const assertPdfDocumentPayload = (document) => {
  const sizeBytes = Number(document?.size_bytes || 0);
  assert(sizeBytes > 0, 'Document size must be greater than zero.');
  assert(sizeBytes <= MAX_DOCUMENT_BYTES, 'Document exceeds allowed size.');
  assert(
    String(document?.mime_type || '').trim().toLowerCase() === 'application/pdf',
    'Only PDF documents are supported.'
  );
  assert(
    String(document?.data_url || '').startsWith('data:application/pdf;base64,'),
    'Document payload must be a PDF data URL.'
  );
};

const toUiEventType = (row) => {
  if ([RUN_STATUSES.FAILED, RUN_STATUSES.FAILED_TIMEOUT, RUN_STATUSES.CANCELLED].includes(row.status)) {
    return 'error';
  }

  if ([RUN_STATUSES.COMPLETED, RUN_STATUSES.COMPLETED_WITH_WARNINGS].includes(row.status)) {
    return 'complete';
  }

  if (row.event_type === 'RUN_ACCEPTED' || row.event_type === 'RUN_STARTED') {
    return 'start';
  }

  return 'progress';
};

const mapEvent = (row) => ({
  id: row.id,
  eventType: row.event_type,
  type: toUiEventType(row),
  agent: row.agent,
  message: row.message,
  ts: row.created_at,
  data: row.payload,
  status: row.status
});

const mapRun = (row, events = []) => ({
  id: row.id,
  kind: row.kind,
  status: row.status,
  attemptCount: row.attempt_count,
  idempotencyKey: row.idempotency_key,
  errorMessage: row.error_message,
  warningSummary: row.warning_summary,
  resultPayload: row.result_payload,
  payload: row.payload,
  queuedAt: row.queued_at,
  startedAt: row.started_at,
  completedAt: row.completed_at,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
  events
});

const mapChunkResult = (row) => ({
  id: row.id,
  runId: row.run_id,
  chunkIndex: row.chunk_index,
  pageStart: row.page_start,
  pageEnd: row.page_end,
  status: row.status,
  attemptCount: row.attempt_count,
  warningCode: row.warning_code,
  errorMessage: row.error_message,
  extractedItemCount: row.extracted_item_count,
  rawExcerptHash: row.raw_excerpt_hash,
  createdAt: row.created_at,
  updatedAt: row.updated_at
});

const assert = (condition, message) => {
  if (!condition) {
    const error = new Error(message);
    error.statusCode = 400;
    throw error;
  }
};

const validateRunPayload = (kind, payload) => {
  const payloadBytes = Buffer.byteLength(JSON.stringify(payload || {}), 'utf8');
  assert(payloadBytes <= MAX_JSON_PAYLOAD_BYTES, 'Payload exceeds allowed size limit.');

  if (kind === RUN_KINDS.ASSIGNMENT_BREAKDOWN) {
    const text = String(payload?.text || '');
    const image = String(payload?.image || '');
    const document = payload?.document || null;

    assert(
      Boolean(text.trim() || image.trim() || document),
      'Assignment breakdown requires text, image, or document input.'
    );
    assert(text.length <= MAX_ASSIGNMENT_TEXT_LENGTH, 'Assignment text exceeds allowed size.');
    if (image) {
      assert(image.length <= MAX_IMAGE_DATA_URL_LENGTH, 'Assignment image exceeds allowed size.');
    }
    if (document) {
      assertPdfDocumentPayload(document);
    }
  }

  if (kind === RUN_KINDS.SUBTASK_BREAKDOWN) {
    const subtask = payload?.subtask || {};
    assert(Boolean(String(subtask.id || '').trim()), 'Subtask breakdown requires a subtask id.');
    assert(Boolean(String(subtask.primary_task_id || '').trim()), 'Subtask breakdown requires a primary_task_id.');
    assert(Boolean(String(subtask.title || '').trim()), 'Subtask breakdown requires a subtask title.');
    assert(Number(subtask.estimated_minutes || 0) > 0, 'Subtask breakdown requires a positive estimated_minutes value.');
  }

  if (kind === RUN_KINDS.SCHEDULE_REBUILD) {
    assert(Array.isArray(payload?.tasks) && payload.tasks.length > 0, 'Schedule rebuild requires task input.');
    assert(Boolean(payload?.start_date), 'Schedule rebuild requires a start_date.');
  }

  if (kind === RUN_KINDS.SYLLABUS_PARSE) {
    const text = String(payload?.text || '');
    const document = payload?.document || null;
    assert(Boolean(text.trim() || document), 'Syllabus parsing requires text or a PDF document.');
    if (document) {
      assertPdfDocumentPayload(document);
    }
  }

  if (kind === RUN_KINDS.TIMETABLE_EXTRACT) {
    assert(Boolean(String(payload?.text || '').trim() || String(payload?.image || '').trim()), 'Timetable extraction requires text or image input.');
  }
};

const appendEvent = async ({
  userId,
  runId,
  attemptCount,
  eventType,
  status,
  agent,
  message,
  payload = null
}) => {
  const { error } = await supabase.from('orchestration_events').insert({
    user_id: userId,
    run_id: runId,
    attempt_count: attemptCount,
    event_type: eventType,
    status,
    agent,
    message,
    payload
  });

  if (error) throw error;
};

export const createRun = async (req, res) => {
  const redis = await getRedis();
  const requestId = req.requestId;
  const { kind, payload = {}, clientKey, sourceSurface = 'dashboard' } = req.body || {};
  let stopHeartbeat = null;
  try {
    if (!clientKey || typeof clientKey !== 'string') {
      return res.status(400).json({ error: 'clientKey is required.' });
    }

    if (!ALLOWED_KINDS.has(kind)) {
      return res.status(400).json({ error: 'Unsupported orchestration kind.' });
    }

    validateRunPayload(kind, payload);

    const payloadHash = sha256(payload);
    const lock = await acquireIdempotencyLock({
      redis,
      userId: req.user.id,
      clientKey,
      payloadHash,
      requestId
    });

    if (lock.state === 'pending') {
      return res.status(409).set('Retry-After', '5').json({
        error: 'In Progress',
        details: 'An equivalent request is already being accepted.'
      });
    }

    if (lock.state === 'accepted') {
      const { data, error } = await supabase
        .from('orchestration_runs')
        .select('*')
        .eq('id', lock.runId)
        .eq('user_id', req.user.id)
        .maybeSingle();

      if (error) {
        return res.status(500).json({ error: 'Failed to load accepted run', details: error.message });
      }

      return res.status(202).json({
        duplicate: true,
        run: data ? mapRun(data) : { id: lock.runId }
      });
    }

    if (lock.state === 'conflict') {
      return res.status(409).json({
        error: 'Conflict',
        details: 'This idempotency key is already bound to a different payload.'
      });
    }

    stopHeartbeat = startPendingHeartbeat({
      redis,
      key: lock.key,
      payloadHash,
      requestId
    });

    const { data: run, error: insertError } = await supabase
      .from('orchestration_runs')
      .insert({
        user_id: req.user.id,
        kind,
        status: RUN_STATUSES.QUEUED,
        attempt_count: 1,
        idempotency_key: clientKey,
        payload_hash: payloadHash,
        request_id: requestId,
        source_surface: sourceSurface,
        payload
      })
      .select('*')
      .single();

    if (insertError) {
      if (insertError.code === '23505') {
        const { data: existingRun } = await supabase
          .from('orchestration_runs')
          .select('*')
          .eq('user_id', req.user.id)
          .eq('idempotency_key', clientKey)
          .maybeSingle();

        if (existingRun && existingRun.payload_hash === payloadHash) {
          await finalizeAcceptedLock({
            redis,
            key: lock.key,
            payloadHash,
            runId: existingRun.id
          });

          return res.status(202).json({
            duplicate: true,
            run: mapRun(existingRun)
          });
        }
      }

      throw insertError;
    }

    await appendEvent({
      userId: req.user.id,
      runId: run.id,
      attemptCount: run.attempt_count,
      eventType: 'RUN_ACCEPTED',
      status: RUN_STATUSES.QUEUED,
      agent: 'orchestrator',
      message: 'Run accepted and queued.',
      payload: { sourceSurface }
    });

    const stream = STREAMS_BY_KIND[kind];
    await publishStreamJob({
      stream,
      payload: {
        request_id: requestId,
        run_id: run.id,
        user_id: req.user.id,
        kind,
        attempt_count: run.attempt_count,
        payload
      }
    });

    await finalizeAcceptedLock({
      redis,
      key: lock.key,
      payloadHash,
      runId: run.id
    });

    res.status(202).json({ run: mapRun(run) });
  } catch (error) {
    const statusCode = Number(error?.statusCode || 500);
    log('error', 'Failed to create orchestration run', {
      requestId,
      userId: req.user.id,
      error
    });
    res.status(statusCode).json({
      error: 'Failed to create orchestration run',
      details: error.message
    });
  } finally {
    stopHeartbeat?.();
  }
};

export const getRun = async (req, res) => {
  try {
    const { id } = req.params;
    const { data: run, error: runError } = await supabase
      .from('orchestration_runs')
      .select('*')
      .eq('id', id)
      .eq('user_id', req.user.id)
      .maybeSingle();

    if (runError) throw runError;
    if (!run) {
      return res.status(404).json({ error: 'Run not found' });
    }

    const { data: events, error: eventError } = await supabase
      .from('orchestration_events')
      .select('*')
      .eq('run_id', id)
      .order('created_at', { ascending: true });

    if (eventError) throw eventError;

    const { data: chunkResults, error: chunkError } = await supabase
      .from('orchestration_chunk_results')
      .select('*')
      .eq('run_id', id)
      .eq('user_id', req.user.id)
      .order('chunk_index', { ascending: true });

    if (chunkError) throw chunkError;

    res.status(200).json({
      run: {
        ...mapRun(run, (events || []).map(mapEvent)),
        chunkResults: (chunkResults || []).map(mapChunkResult)
      }
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to load orchestration run',
      details: error.message
    });
  }
};

export const getOverview = async (req, res) => {
  try {
    const [runsResult, eventsResult] = await Promise.all([
      supabase
        .from('orchestration_runs')
        .select('*')
        .eq('user_id', req.user.id)
        .order('updated_at', { ascending: false })
        .limit(20),
      supabase
        .from('orchestration_events')
        .select('*')
        .eq('user_id', req.user.id)
        .order('created_at', { ascending: false })
        .limit(100)
    ]);

    if (runsResult.error) throw runsResult.error;
    if (eventsResult.error) throw eventsResult.error;

    res.status(200).json({
      runs: runsResult.data || [],
      events: eventsResult.data || []
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to load orchestration overview',
      details: error.message
    });
  }
};

export const retryRun = async (req, res) => {
  try {
    const { id } = req.params;
    const { data: run, error: runError } = await supabase
      .from('orchestration_runs')
      .select('*')
      .eq('id', id)
      .eq('user_id', req.user.id)
      .maybeSingle();

    if (runError) throw runError;
    if (!run) {
      return res.status(404).json({ error: 'Run not found' });
    }

    if (!isTerminalRunStatus(run.status)) {
      return res.status(409).json({ error: 'Only terminal runs can be retried.' });
    }

    const nextAttempt = Number(run.attempt_count || 1) + 1;
    const { data: updatedRun, error: updateError } = await supabase
      .from('orchestration_runs')
      .update({
        status: RUN_STATUSES.QUEUED,
        attempt_count: nextAttempt,
        error_message: null,
        warning_summary: {},
        result_payload: {},
        started_at: null,
        completed_at: null,
        lease_expires_at: null
      })
      .eq('id', id)
      .eq('user_id', req.user.id)
      .select('*')
      .single();

    if (updateError) throw updateError;

    await appendEvent({
      userId: req.user.id,
      runId: id,
      attemptCount: nextAttempt,
      eventType: 'RUN_REQUEUED',
      status: RUN_STATUSES.QUEUED,
      agent: 'orchestrator',
      message: 'Run requeued for retry.'
    });

    await publishStreamJob({
      stream: STREAMS_BY_KIND[updatedRun.kind],
      payload: {
        request_id: req.requestId,
        run_id: updatedRun.id,
        user_id: req.user.id,
        kind: updatedRun.kind,
        attempt_count: updatedRun.attempt_count,
        payload: updatedRun.payload
      }
    });

    res.status(202).json({ run: mapRun(updatedRun) });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to retry run',
      details: error.message
    });
  }
};

export const cancelRun = async (req, res) => {
  try {
    const { id } = req.params;
    const { data: run, error: runError } = await supabase
      .from('orchestration_runs')
      .select('*')
      .eq('id', id)
      .eq('user_id', req.user.id)
      .maybeSingle();

    if (runError) throw runError;
    if (!run) {
      return res.status(404).json({ error: 'Run not found' });
    }

    if (isTerminalRunStatus(run.status)) {
      return res.status(409).json({ error: 'Terminal runs cannot be cancelled.' });
    }

    const { data: updatedRun, error: updateError } = await supabase
      .from('orchestration_runs')
      .update({
        status: RUN_STATUSES.CANCELLED,
        error_message: 'Cancelled by user request.',
        completed_at: new Date().toISOString()
      })
      .eq('id', id)
      .eq('user_id', req.user.id)
      .select('*')
      .single();

    if (updateError) throw updateError;

    await appendEvent({
      userId: req.user.id,
      runId: id,
      attemptCount: updatedRun.attempt_count,
      eventType: 'RUN_CANCELLED',
      status: RUN_STATUSES.CANCELLED,
      agent: 'orchestrator',
      message: 'Run cancelled by user request.'
    });

    res.status(200).json({ run: mapRun(updatedRun) });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to cancel run',
      details: error.message
    });
  }
};
