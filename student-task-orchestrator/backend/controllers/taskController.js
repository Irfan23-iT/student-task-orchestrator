import { supabase } from '../config/supabase.js';
import { syncEngagementForUser } from '../lib/engagementProgress.js';
import { isMissingTableError } from '../lib/tableErrors.js';

const PRIORITY_SCORES = {
  high: 90,
  medium: 60,
  low: 30
};

const normalizePriorityBand = (value, fallback = 'medium') => {
  const normalized = String(value || '').trim().toLowerCase();
  if (Object.prototype.hasOwnProperty.call(PRIORITY_SCORES, normalized)) {
    return normalized;
  }
  return fallback;
};

const normalizePriorityLevel = (value) => {
  const normalized = String(value ?? 'Medium').trim().toLowerCase();
  if (normalized === 'low') return 'Low';
  if (normalized === 'high') return 'High';
  return 'Medium';
};

const normalizeTaskStatus = (value) => {
  const normalized = String(value ?? 'pending').trim().toLowerCase();
  if (normalized === 'completed' || normalized === 'done') return 'DONE';
  if (normalized === 'cancelled' || normalized === 'canceled' || normalized === 'archived') return 'DONE';
  if (normalized === 'in progress' || normalized === 'in_progress') return 'IN_PROGRESS';
  return 'TODO';
};

const normalizeTaskType = (value) => {
  const normalized = String(value ?? 'general').trim().toLowerCase();
  if (['exam', 'assignment', 'event', 'reminder'].includes(normalized)) {
    return normalized;
  }
  return 'general';
};

const CORE_TASK_COLUMNS =
  'id, user_id, title, description, due_date, priority_level, status, task_type, category_id, notes, created_at, categories(id, name, color_hex)';
const CORE_TASK_METADATA_COLUMNS =
  'id, user_id, title, description, due_date, priority_level, status, task_type, category_id, notes, created_at';
const CORE_TASK_LEAN_COLUMNS =
  'id, user_id, title, description, due_date, priority_level, is_completed, created_at';
const SUB_TASK_COLUMNS =
  'id, parent_task_id, title, estimated_minutes, status, is_chunked, scheduled_date, scheduled_start_time, scheduled_end_time, pipeline_run_id, client_task_key, primary_task_id, priority_score, priority_band, priority_reason, manual_priority_override, user_id, due_date, is_completed, created_at';
const SUB_TASK_LEAN_COLUMNS =
  'id, primary_task_id, title, due_date, is_completed, created_at';
const PRIMARY_TASK_COLUMNS =
  'id, user_id, title, description, status, due_date, task_type, category_id, notes, total_subtasks, created_at, categories(id, name, color_hex)';
const PRIMARY_TASK_METADATA_COLUMNS =
  'id, user_id, title, description, status, due_date, task_type, category_id, notes, total_subtasks, created_at';
const PRIMARY_TASK_LEAN_COLUMNS =
  'id, user_id, title, total_subtasks, created_at';

const uniqueNonEmptyStrings = (values = []) => [
  ...new Set(
    values
      .map((value) => String(value || '').trim())
      .filter(Boolean)
  )
];

const readReminderJobsForUser = async (db, userId) => {
  const { data, error } = await db
    .from('reminder_jobs')
    .select('id, sub_task_id, payload')
    .eq('user_id', userId);

  if (error) {
    if (isMissingTableError(error, 'reminder_jobs')) return [];
    throw error;
  }

  return data || [];
};

const getReminderPayloadTaskId = (job = {}) => {
  const payload = job.payload && typeof job.payload === 'object' ? job.payload : {};
  return payload.task_id || payload.taskId || null;
};

const deleteReminderJobs = async ({ db, userId, reminderJobIds }) => {
  const ids = uniqueNonEmptyStrings(reminderJobIds);
  if (ids.length === 0) return;

  const { error: deliveryDeleteError } = await db
    .from('reminder_deliveries')
    .delete()
    .eq('user_id', userId)
    .in('reminder_job_id', ids);

  if (deliveryDeleteError && !isMissingTableError(deliveryDeleteError, 'reminder_deliveries')) {
    throw deliveryDeleteError;
  }

  const { error: reminderDeleteError } = await db
    .from('reminder_jobs')
    .delete()
    .eq('user_id', userId)
    .in('id', ids);

  if (reminderDeleteError && !isMissingTableError(reminderDeleteError, 'reminder_jobs')) {
    throw reminderDeleteError;
  }
};

const deleteRemindersForTaskIds = async ({ db, userId, taskIds }) => {
  const targetIds = new Set(uniqueNonEmptyStrings(taskIds));
  if (targetIds.size === 0) return;

  const reminderJobs = await readReminderJobsForUser(db, userId);
  const matchingJobIds = reminderJobs
    .filter((job) => (
      targetIds.has(String(job.sub_task_id || '')) ||
      targetIds.has(String(getReminderPayloadTaskId(job) || ''))
    ))
    .map((job) => job.id);

  await deleteReminderJobs({ db, userId, reminderJobIds: matchingJobIds });
};

const deleteAllRemindersForUser = async ({ db, userId }) => {
  const reminderJobs = await readReminderJobsForUser(db, userId);
  await deleteReminderJobs({
    db,
    userId,
    reminderJobIds: reminderJobs.map((job) => job.id)
  });
};

const isSchemaColumnError = (error) => {
  const message = String(error?.message || '');
  return (
    error?.code === 'PGRST204' ||
    /could not find|does not exist|schema cache|column/i.test(message)
  );
};

const isRelationshipSchemaError = (error) => {
  const message = String(error?.message || '');
  return error?.code === 'PGRST200' || /relationship/i.test(message);
};

const normalizeDueDate = (value) => {
  if (value == null || value === '') return null;
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    const error = new Error('dueDate must be a valid ISO date string.');
    error.statusCode = 400;
    throw error;
  }
  return parsed.toISOString();
};

const assert = (condition, message, statusCode = 400) => {
  if (condition) return;
  const error = new Error(message);
  error.statusCode = statusCode;
  throw error;
};

const getErrorStatusCode = (error) => {
  if (Number.isInteger(error?.statusCode)) return error.statusCode;
  if (error?.code === '23514' || error?.code === '22P02' || error?.code === '23502') return 400;
  return 500;
};

const isCompletedStatus = (value) => {
  const normalized = String(value || '').trim().toLowerCase();
  return normalized === 'completed' || normalized === 'done';
};

const toTaskResponse = (row = {}) => ({
  id: row.id,
  user_id: row.user_id,
  title: row.title,
  description: row.description,
  due_date: row.due_date,
  priority_level: row.priority_level,
  priority_band: row.priority_level,
  status: row.status ?? (row.is_completed ? 'completed' : 'pending'),
  task_type: row.task_type ?? 'general',
  category_id: row.category_id ?? row.categories?.id ?? null,
  category: row.categories ?? null,
  notes: row.notes ?? null,
  is_completed: row.is_completed ?? isCompletedStatus(row.status),
  created_at: row.created_at
});

const toTaskInsert = (userId, body = {}) => {
  const title = String(body.title ?? '').trim();
  assert(title.length > 0, 'Task title is required.');

  const description =
    body.description == null || String(body.description).trim() === ''
      ? null
      : String(body.description).trim();

  const insertPayload = {
    user_id: userId,
    title,
    description,
    due_date: normalizeDueDate(body.dueDate ?? body.due_date),
    priority_level: normalizePriorityLevel(body.priorityLevel ?? body.priority_level ?? body.priority),
    status: normalizeTaskStatus(body.status),
    task_type: normalizeTaskType(body.taskType ?? body.task_type),
  };

  const categoryId = body.categoryId ?? body.category_id;
  if (categoryId != null && String(categoryId).trim() !== '') {
    insertPayload.category_id = String(categoryId).trim();
  }

  const notes = body.notes;
  if (notes != null && String(notes).trim() !== '') {
    insertPayload.notes = String(notes).trim();
  }

  return insertPayload;
};

export const getTasks = async (req, res) => {
  try {
    const userId = req.user.id;
    const { startDate, endDate } = req.query || {};

    const db = req.supabase || supabase;
    const buildQuery = (columns) => {
      let query = db
        .from('tasks')
        .select(columns)
        .eq('user_id', userId);

      if (startDate) {
        query = query.gte('due_date', startDate);
      }

      if (endDate) {
        query = query.lte('due_date', endDate);
      }

      return query.order('created_at', { ascending: false });
    };

    let { data: tasks, error } = await buildQuery(CORE_TASK_COLUMNS);
    if (error && isRelationshipSchemaError(error)) {
      ({ data: tasks, error } = await buildQuery(CORE_TASK_METADATA_COLUMNS));
    }

    if (error && isSchemaColumnError(error)) {
      ({ data: tasks, error } = await buildQuery(CORE_TASK_LEAN_COLUMNS));
    }

    if (error) {
      throw error;
    }

    res.status(200).json({ tasks: (tasks || []).map(toTaskResponse) });
  } catch (error) {
    const statusCode = getErrorStatusCode(error);
    console.error('Task Fetch Failed:', error.message || error);
    res.status(statusCode).json({
      error: error.message || 'Failed to fetch tasks',
      details: error.message || 'Unknown error'
    });
  }
};

export const createTask = async (req, res) => {
  try {
    const userId = req.user.id;
    const db = req.supabase || supabase;

    let insertPayload = toTaskInsert(userId, req.body || {});
    let { data, error } = await db
      .from('tasks')
      .insert(insertPayload)
      .select(CORE_TASK_METADATA_COLUMNS)
      .single();

    if (error && isSchemaColumnError(error)) {
      const { status, task_type, category_id, notes, ...leanInsertPayload } = insertPayload;
      insertPayload = leanInsertPayload;
      ({ data, error } = await db
        .from('tasks')
        .insert(insertPayload)
        .select(CORE_TASK_LEAN_COLUMNS)
        .single());
    }

    if (error) throw error;

    res.status(201).json({ task: toTaskResponse(data) });
  } catch (error) {
    const statusCode = getErrorStatusCode(error);
    console.error('Task Creation Failed:', error.message, 'Payload:', req.body);
    res.status(statusCode).json({
      error: error.message,
      details: error.message
    });
  }
};

export const getTaskRows = async (req, res) => {
  try {
    const userId = req.user.id;
    const db = req.supabase || supabase;
    let { data, error } = await db
      .from('sub_tasks')
      .select(SUB_TASK_COLUMNS)
      .eq('user_id', userId)
      .order('created_at', { ascending: true });

    if (error && isSchemaColumnError(error)) {
      ({ data, error } = await db
        .from('sub_tasks')
        .select(SUB_TASK_LEAN_COLUMNS)
        .eq('user_id', userId)
        .order('created_at', { ascending: true }));
    }

    if (error) throw error;

    res.status(200).json({ rows: data || [] });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to fetch task rows',
      details: error.message
    });
  }
};

export const getPrimaryTasks = async (req, res) => {
  try {
    const userId = req.user.id;
    const { startDate, endDate } = req.query || {};

    const db = req.supabase || supabase;
    const buildQuery = (columns) => {
      let query = db
        .from('primary_tasks')
        .select(columns)
        .eq('user_id', userId);

      if (startDate) {
        query = query.gte('due_date', startDate);
      }

      if (endDate) {
        query = query.lte('due_date', endDate);
      }

      return query.order('created_at', { ascending: false });
    };

    let { data: primaryTasks, error } = await buildQuery(PRIMARY_TASK_COLUMNS);
    if (error && isRelationshipSchemaError(error)) {
      ({ data: primaryTasks, error } = await buildQuery(PRIMARY_TASK_METADATA_COLUMNS));
    }

    if (error && isSchemaColumnError(error)) {
      ({ data: primaryTasks, error } = await buildQuery(PRIMARY_TASK_LEAN_COLUMNS));
    }

    if (error) {
      throw error;
    }

    res.status(200).json({ primaryTasks: primaryTasks || [] });
  } catch (error) {
    const statusCode = getErrorStatusCode(error);
    console.error('Primary Task Fetch Failed:', error.message || error);
    res.status(statusCode).json({
      error: error.message || 'Failed to fetch primary tasks',
      details: error.message || 'Unknown error'
    });
  }
};

export const updateSubTask = async (req, res) => {
  try {
    const { id } = req.params;
    const { completed } = req.body;
    const status = completed ? 'completed' : 'pending';
    const userId = req.user.id;

    const { data: verify, error: verifyError } = await supabase
      .from('sub_tasks')
      .select('id, primary_task_id, title')
      .eq('id', id)
      .eq('user_id', userId)
      .maybeSingle();

    if (verifyError) {
      throw verifyError;
    }

    if (!verify) {
      const { data: task, error: taskError } = await supabase
        .from('tasks')
        .update({
          status: completed ? 'completed' : 'pending'
        })
        .eq('id', id)
        .eq('user_id', userId)
        .select('*')
        .maybeSingle();

      if (taskError) throw taskError;
      if (!task) {
        return res.status(403).json({ error: "Access denied or task not found" });
      }

      return res.status(200).json({ task: toTaskResponse(task) });
    }

    const { data, error } = await supabase
      .from('sub_tasks')
      .update({
        status
      })
      .eq('id', id)
      .eq('user_id', userId)
      .select()
      .single();

    if (error) throw error;

    if (completed) {
      const { data: existingCompletionEvent, error: completionEventLookupError } = await supabase
        .from('completion_events')
        .select('id')
        .eq('user_id', userId)
        .eq('sub_task_id', id)
        .maybeSingle();

      if (completionEventLookupError) throw completionEventLookupError;

      if (!existingCompletionEvent) {
        const { error: completionEventInsertError } = await supabase
          .from('completion_events')
          .insert({
            user_id: userId,
            sub_task_id: id,
            completed_at: new Date().toISOString(),
            source_surface: 'dashboard',
            payload: {
              title: data.title || verify.title || 'Completed task'
            }
          });

        if (completionEventInsertError) throw completionEventInsertError;
      }
    } else {
      const { error: deleteCompletionEventError } = await supabase
        .from('completion_events')
        .delete()
        .eq('user_id', userId)
        .eq('sub_task_id', id);

      if (deleteCompletionEventError) throw deleteCompletionEventError;
    }

    // --- SYNC PARENT TASK STATUS ---
    // After updating the sub-task, check if ALL sub-tasks for this parent are now completed
    const primaryTaskId = data.primary_task_id || verify.primary_task_id;
    const { data: siblingSubTasks, error: siblingError } = await supabase
      .from('sub_tasks')
      .select('status')
      .eq('primary_task_id', primaryTaskId)
      .eq('user_id', userId);

    if (!siblingError && siblingSubTasks) {
      const allCompleted = siblingSubTasks.length > 0 && siblingSubTasks.every(st => st.status === 'completed');
      
      await supabase
        .from('primary_tasks')
        .update({ status: allCompleted ? 'completed' : 'pending' })
        .eq('id', primaryTaskId)
        .eq('user_id', userId);
        
      console.log(`[Sync] Parent Task ${primaryTaskId} status set to: ${allCompleted ? 'completed' : 'pending'}`);
    }

    await syncEngagementForUser(userId);

    res.status(200).json({ subTask: data });
  } catch (error) {
    console.error("Error updating subtask:", error);
    res.status(500).json({ error: "Failed to update subtask" });
  }
};

export const saveTasksForRun = async (req, res) => {
  try {
    const { runId, courseTitle, tasks } = req.body || {};
    const userId = req.user.id;

    if (!runId || !courseTitle || !Array.isArray(tasks) || tasks.length === 0) {
      return res.status(400).json({
        error: 'runId, courseTitle, and tasks are required.'
      });
    }

    const { error: pipelineRunError } = await supabase
      .from('ingest_pipeline_runs')
      .upsert(
        {
          id: runId,
          user_id: userId,
          phase: 'IDLE',
          status: 'IDLE',
          last_completed_phase: 'IDLE',
          logical_task_ids: [],
          schedule_rows: [],
          retry_counts: {},
          recoverable: false,
          optimizer_payload: {
            source: 'mobile_ai_orchestrator',
            courseTitle,
          },
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'id' },
      );

    if (pipelineRunError) {
      console.error('Supabase ingest_pipeline_runs upsert failed:', {
        userId,
        runId,
        courseTitle,
        error: pipelineRunError,
      });
      throw pipelineRunError;
    }

    const { data: primaryTask, error: primaryTaskError } = await supabase
      .from('primary_tasks')
      .upsert(
        [
          {
            user_id: userId,
            title: courseTitle,
            description: 'AI generated',
            status: 'pending',
            pipeline_run_id: runId,
            client_ingest_key: `ingest:${runId}`
          }
        ],
        { onConflict: 'client_ingest_key' }
      )
      .select('id')
      .single();

    if (primaryTaskError) {
      console.error('Supabase primary_tasks upsert failed:', {
        userId,
        runId,
        courseTitle,
        error: primaryTaskError
      });
      throw primaryTaskError;
    }

    const insertPayload = tasks.map((task, index) => {
      const priorityBand = normalizePriorityBand(task.priority_band || task.priority, 'medium');
      return {
        user_id: userId,
        primary_task_id: primaryTask.id,
        title: task.title,
        estimated_minutes: parseInt(task.duration, 10) || parseInt(task.duration_minutes, 10) || 30,
        status: 'pending',
        priority: priorityBand,
        priority_score: PRIORITY_SCORES[priorityBand],
        priority_band: priorityBand,
        priority_reason: task.priority_reason || 'Generated from assignment breakdown.',
        manual_priority_override: false,
        pipeline_run_id: runId,
        client_task_key: `${runId}:${index}`
      };
    });

    const { data: insertedRows, error: subTaskInsertError } = await supabase
      .from('sub_tasks')
      .upsert(insertPayload, { onConflict: 'client_task_key' })
      .select('*');

    if (subTaskInsertError) {
      console.error('Supabase sub_tasks upsert failed:', {
        userId,
        runId,
        primaryTaskId: primaryTask.id,
        insertPayload,
        error: subTaskInsertError
      });
      throw subTaskInsertError;
    }

    res.status(200).json({
      primaryTaskId: primaryTask.id,
      rows: insertedRows || []
    });
  } catch (error) {
    console.error('saveTasksForRun failed:', error);
    res.status(500).json({
      error: 'Failed to save tasks for run',
      details: error.message
    });
  }
};

export const getTasksByRun = async (req, res) => {
  try {
    const { runId } = req.params;
    const userId = req.user.id;
    const { data, error } = await supabase
      .from('sub_tasks')
      .select('*')
      .eq('pipeline_run_id', runId)
      .eq('user_id', userId)
      .order('created_at', { ascending: true });

    if (error) throw error;

    res.status(200).json({ rows: data || [] });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to fetch tasks by run',
      details: error.message
    });
  }
};

export const deleteSessionTasks = async (req, res) => {
  try {
    const userId = req.user.id;
    const db = req.supabase || supabase;
    const primaryTaskIds = Array.isArray(req.body?.primaryTaskIds) ? req.body.primaryTaskIds : [];
    const subTaskIds = Array.isArray(req.body?.subTaskIds) ? req.body.subTaskIds : [];
    const pipelineRunId = req.body?.pipelineRunId || null;
    const reminderTaskIds = [];

    if (subTaskIds.length > 0) {
      const { data: allowedRows, error: selectError } = await db
        .from('sub_tasks')
        .select('id')
        .in('id', subTaskIds)
        .eq('user_id', userId);

      if (selectError) throw selectError;

      const allowedIds = (allowedRows || []).map((row) => row.id);
      reminderTaskIds.push(...allowedIds);

      const { data: allowedCoreTaskRows, error: coreTaskSelectError } = await db
        .from('tasks')
        .select('id')
        .eq('user_id', userId)
        .in('id', subTaskIds);

      if (coreTaskSelectError) throw coreTaskSelectError;

      reminderTaskIds.push(...(allowedCoreTaskRows || []).map((row) => row.id));

      await deleteRemindersForTaskIds({ db, userId, taskIds: reminderTaskIds });

      if (allowedIds.length > 0) {
        const { error: deleteSubTasksError } = await db
          .from('sub_tasks')
          .delete()
          .eq('user_id', userId)
          .in('id', allowedIds);

        if (deleteSubTasksError) throw deleteSubTasksError;
      }

      const { error: deleteTasksError } = await db
        .from('tasks')
        .delete()
        .eq('user_id', userId)
        .in('id', subTaskIds);

      if (deleteTasksError) throw deleteTasksError;
    }

    if (primaryTaskIds.length > 0) {
      const { data: primarySubTasks, error: primarySubTasksError } = await db
        .from('sub_tasks')
        .select('id')
        .eq('user_id', userId)
        .in('primary_task_id', primaryTaskIds);

      if (primarySubTasksError) throw primarySubTasksError;

      await deleteRemindersForTaskIds({
        db,
        userId,
        taskIds: [
          ...primaryTaskIds,
          ...(primarySubTasks || []).map((row) => row.id)
        ]
      });

      const { error: deletePrimaryTasksError } = await db
        .from('primary_tasks')
        .delete()
        .eq('user_id', userId)
        .in('id', primaryTaskIds);

      if (deletePrimaryTasksError) throw deletePrimaryTasksError;
    }

    if (pipelineRunId) {
      await db
        .from('ingest_pipeline_runs')
        .update({
          status: 'CANCELLED',
          recoverable: false,
          error_message: 'Pipeline cancelled during task purge.'
        })
        .eq('id', pipelineRunId)
        .eq('user_id', userId);
    }

    res.status(200).json({ success: true });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to clear session tasks',
      details: error.message
    });
  }
};

export const deleteTask = async (req, res) => {
  try {
    const userId = req.user.id;
    const db = req.supabase || supabase;
    const taskId = String(req.params?.id || '').trim();

    assert(taskId.length > 0, 'Task id is required.');

    const { data: task, error: taskLookupError } = await db
      .from('tasks')
      .select('id')
      .eq('id', taskId)
      .eq('user_id', userId)
      .maybeSingle();

    if (taskLookupError) throw taskLookupError;

    if (!task) {
      const { data: subTask, error: subTaskLookupError } = await db
        .from('sub_tasks')
        .select('id')
        .eq('id', taskId)
        .eq('user_id', userId)
        .maybeSingle();

      if (subTaskLookupError) throw subTaskLookupError;

      if (!subTask) {
        return res.status(404).json({ error: 'Task not found' });
      }

      await deleteRemindersForTaskIds({ db, userId, taskIds: [taskId] });

      const { error: deleteSubTaskError } = await db
        .from('sub_tasks')
        .delete()
        .eq('id', taskId)
        .eq('user_id', userId);

      if (deleteSubTaskError) throw deleteSubTaskError;

      return res.status(200).json({ success: true, id: taskId });
    }

    await deleteRemindersForTaskIds({ db, userId, taskIds: [taskId] });

    const { error: deleteTaskError } = await db
      .from('tasks')
      .delete()
      .eq('id', taskId)
      .eq('user_id', userId);

    if (deleteTaskError) throw deleteTaskError;

    res.status(200).json({ success: true, id: taskId });
  } catch (error) {
    const statusCode = getErrorStatusCode(error);
    console.error('Error deleting task:', error);
    res.status(statusCode).json({
      error: statusCode === 400 ? error.message : 'Failed to delete task',
      details: error.message
    });
  }
};

export const deleteAllTasks = async (req, res) => {
  try {
    const userId = req.user.id;
    const db = req.supabase || supabase;

    await deleteAllRemindersForUser({ db, userId });

    const { error: coreTasksError } = await db
      .from('tasks')
      .delete()
      .eq('user_id', userId);

    if (coreTasksError) throw coreTasksError;

    const { error } = await db
      .from('primary_tasks')
      .delete()
      .eq('user_id', userId);

    if (error) throw error;
    res.status(200).json({ message: "All tasks cleared successfully" });
  } catch (error) {
    console.error("Error deleting tasks:", error);
    res.status(500).json({ error: "Failed to clear tasks" });
  }
};
