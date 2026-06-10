import { supabase } from '../config/supabase.js';
import {
  buildReminderActionMutation,
  normalizeNotificationPreferences,
  normalizePushSubscriptionPayload,
  normalizeReminderActionPayload,
  normalizeReminderPayload
} from '../lib/analyticsNotifications.js';
import { getNotificationDeliveryCapabilities } from '../lib/notificationService.js';
import { log } from '../lib/logger.js';
import { isMissingTableError } from '../lib/tableErrors.js';

const assert = (condition, message, statusCode = 400) => {
  if (condition) return;
  const error = new Error(message);
  error.statusCode = statusCode;
  throw error;
};

const MAX_REMINDER_LEAD_MINUTES = 7 * 24 * 60;

const isMissingConflictConstraintError = (error) => {
  const message = `${error?.message || error?.details || ''}`.toLowerCase();
  return message.includes('there is no unique or exclusion constraint matching the on conflict specification');
};

const upsertReminderDeliveries = async (deliveries = []) => {
  if (!deliveries.length) return;

  const { error } = await supabase
    .from('reminder_deliveries')
    .upsert(deliveries, { onConflict: 'reminder_job_id,channel' });

  if (!error) return;
  if (!isMissingConflictConstraintError(error)) throw error;

  await Promise.all(
    deliveries.map(async (delivery) => {
      const { data: existing, error: selectError } = await supabase
        .from('reminder_deliveries')
        .select('id')
        .eq('reminder_job_id', delivery.reminder_job_id)
        .eq('channel', delivery.channel)
        .maybeSingle();

      if (selectError && !isMissingTableError(selectError, 'reminder_deliveries')) throw selectError;

      if (existing?.id) {
        const { error: updateError } = await supabase
          .from('reminder_deliveries')
          .update(delivery)
          .eq('id', existing.id);

        if (updateError) throw updateError;
        return;
      }

      const { error: insertError } = await supabase.from('reminder_deliveries').insert(delivery);
      if (insertError) throw insertError;
    })
  );
};

const readUserTable = async ({
  table,
  userId,
  select = '*',
  orderBy = null,
  ascending = false,
  allowMissing = false,
  fallbackValue = []
}) => {
  const builder = supabase.from(table).select(select).eq('user_id', userId);
  if (orderBy) {
    builder.order(orderBy, { ascending });
  }

  const { data, error } = await builder;
  if (!error) {
    return {
      data: data || fallbackValue,
      missing: false
    };
  }

  if (allowMissing && isMissingTableError(error, table)) {
    return {
      data: fallbackValue,
      missing: true
    };
  }

  throw error;
};

const readSingleUserRow = async ({
  table,
  userId,
  select = '*',
  allowMissing = false,
  fallbackValue = null
}) => {
  const { data, error } = await supabase
    .from(table)
    .select(select)
    .eq('user_id', userId)
    .maybeSingle();

  if (!error) {
    return {
      data: data || fallbackValue,
      missing: false
    };
  }

  if (allowMissing && isMissingTableError(error, table)) {
    return {
      data: fallbackValue,
      missing: true
    };
  }

  throw error;
};

const ensureReminderChannelReady = async ({ userId, channel, notificationPreferences }) => {
  if (channel === 'inbox') {
    assert(Boolean(notificationPreferences.inboxEnabled), 'Inbox reminders are disabled in notification preferences.');
    return;
  }

  if (channel === 'email') {
    assert(Boolean(notificationPreferences.emailEnabled), 'Email reminders are disabled in notification preferences.');
    const capabilities = getNotificationDeliveryCapabilities();
    assert(Boolean(capabilities.emailConfigured), 'Email delivery is not configured.');

    const { data: userRow, error } = await supabase.from('users').select('email').eq('id', userId).maybeSingle();
    if (error) throw error;
    assert(Boolean(userRow?.email), 'No account email found for email reminders.');
    return;
  }

  if (channel === 'push') {
    const { data: subscriptions, error } = await supabase
      .from('web_push_subscriptions')
      .select('id')
      .eq('user_id', userId)
      .limit(1);

    if (error) throw error;
    assert(Boolean(subscriptions?.length), 'Register this browser before scheduling push reminders.');
  }
};

const REMINDER_TASK_TABLES = [
  { type: 'task', table: 'tasks' },
  { type: 'primary_task', table: 'primary_tasks' },
  { type: 'sub_task', table: 'sub_tasks' }
];

const normalizeReminderTaskType = (taskType = '') => {
  const normalized = `${taskType || ''}`.trim().toLowerCase();
  if (['task', 'tasks', 'standard', 'standard_task'].includes(normalized)) return 'task';
  if (['primary', 'primary_task', 'primary_tasks'].includes(normalized)) return 'primary_task';
  if (['sub', 'subtask', 'sub_task', 'sub_tasks'].includes(normalized)) return 'sub_task';
  return '';
};

const getReminderTaskCandidates = (taskType = '') => {
  const normalizedType = normalizeReminderTaskType(taskType);
  if (!normalizedType) return REMINDER_TASK_TABLES;

  return [
    REMINDER_TASK_TABLES.find((candidate) => candidate.type === normalizedType),
    ...REMINDER_TASK_TABLES.filter((candidate) => candidate.type !== normalizedType)
  ].filter(Boolean);
};

const readOwnedSubTask = async (userId, taskId) => {
  const { data: directSubTask, error: directError } = await supabase
    .from('sub_tasks')
    .select('id, user_id, primary_task_id')
    .eq('id', taskId)
    .maybeSingle();

  if (directError) throw directError;
  if (!directSubTask?.id) return null;
  if (directSubTask.user_id === userId) {
    return {
      id: directSubTask.id,
      table: 'sub_tasks',
      type: 'sub_task'
    };
  }

  if (!directSubTask.primary_task_id) return null;

  const { data: parentTask, error: parentError } = await supabase
    .from('primary_tasks')
    .select('id')
    .eq('id', directSubTask.primary_task_id)
    .eq('user_id', userId)
    .maybeSingle();

  if (parentError) throw parentError;
  if (!parentTask?.id) return null;

  return {
    id: directSubTask.id,
    table: 'sub_tasks',
    type: 'sub_task'
  };
};

const readOwnedTask = async ({ userId, taskId, table, type }) => {
  if (table === 'sub_tasks') {
    return readOwnedSubTask(userId, taskId);
  }

  const { data, error } = await supabase
    .from(table)
    .select('id')
    .eq('id', taskId)
    .eq('user_id', userId)
    .maybeSingle();

  if (error) throw error;
  if (!data?.id) return null;

  return {
    id: data.id,
    table,
    type
  };
};

const assertOwnedReminderTask = async ({ userId, taskId, taskType }) => {
  assert(Boolean(String(taskId || '').trim()), 'Reminder taskId is required.');

  for (const candidate of getReminderTaskCandidates(taskType)) {
    const task = await readOwnedTask({
      userId,
      taskId,
      table: candidate.table,
      type: candidate.type
    });

    if (task) return task;
  }

  assert(false, 'Task not found.', 404);
};

export const getAnalyticsOverview = async (req, res) => {
  try {
    const userId = req.user.id;
    const [
      completionEventsResult,
      reminderJobsResult,
      reminderDeliveriesResult,
      notificationPreferencesResult,
      pushSubscriptionsResult,
      userBadgesResult,
      badgeCatalogResult,
      productivityDailyStatsResult,
      streakSnapshotResult,
      orchestrationRunsResult,
      taskRowsResult
    ] = await Promise.all([
      readUserTable({
        table: 'completion_events',
        userId,
        orderBy: 'completed_at'
      }),
      readUserTable({
        table: 'reminder_jobs',
        userId,
        orderBy: 'reminder_at',
        ascending: true
      }),
      readUserTable({
        table: 'reminder_deliveries',
        userId,
        orderBy: 'created_at'
      }),
      readSingleUserRow({
        table: 'notification_preferences',
        userId
      }),
      readUserTable({
        table: 'web_push_subscriptions',
        userId,
        orderBy: 'updated_at'
      }),
      readUserTable({
        table: 'user_badges',
        userId,
        orderBy: 'awarded_at'
      }),
      (async () => {
        const { data, error } = await supabase.from('badges').select('*');
        if (error) throw error;
        return { data: data || [], missing: false };
      })(),
      (async () => {
        const { data, error } = await supabase
          .from('productivity_daily_stats')
          .select('*')
          .eq('user_id', userId)
          .order('stat_day', { ascending: false })
          .limit(1)
          .maybeSingle();
        if (error && !isMissingTableError(error, 'productivity_daily_stats')) throw error;
        return { data: data || null, missing: Boolean(error) };
      })(),
      (async () => {
        const { data, error } = await supabase
          .from('streak_snapshots')
          .select('*')
          .eq('user_id', userId)
          .order('streak_day', { ascending: false })
          .limit(1)
          .maybeSingle();
        if (error && !isMissingTableError(error, 'streak_snapshots')) throw error;
        return { data: data || null, missing: Boolean(error) };
      })(),
      readUserTable({
        table: 'orchestration_runs',
        userId,
        orderBy: 'updated_at',
        allowMissing: false
      }),
      readUserTable({
        table: 'sub_tasks',
        userId,
        // `sub_tasks` is created without an `updated_at` column in the current schema.
        orderBy: 'created_at',
        allowMissing: false
      })
    ]);

    const normalizedPreferences = normalizeNotificationPreferences(notificationPreferencesResult.data);

    res.status(200).json({
      storageMode: 'remote',
      completionEvents: completionEventsResult.data,
      reminderJobs: reminderJobsResult.data,
      reminderDeliveries: reminderDeliveriesResult.data,
      notificationPreferences: normalizedPreferences,
      pushSubscriptions: pushSubscriptionsResult.data,
      userBadges: userBadgesResult.data,
      badgeCatalog: badgeCatalogResult.data,
      productivityDailyStats: productivityDailyStatsResult.data,
      streakSnapshot: streakSnapshotResult.data,
      orchestrationRuns: orchestrationRunsResult.data,
      tasks: taskRowsResult.data,
      deliveryCapabilities: getNotificationDeliveryCapabilities()
    });
  } catch (error) {
    log('error', 'Failed to load analytics overview', {
      requestId: req.requestId,
      userId: req.user.id,
      error
    });
    res.status(500).json({
      error: 'Failed to load analytics overview',
      details: error.message
    });
  }
};

export const upsertNotificationPreferences = async (req, res) => {
  try {
    const userId = req.user.id;
    const payload = normalizeNotificationPreferences(req.body || {});
    const reminderLeadMinutes = Number.parseInt(payload.reminderLeadMinutes, 10);

    assert(Number.isFinite(reminderLeadMinutes), 'Reminder lead minutes must be a whole number.');
    assert(
      reminderLeadMinutes >= 5 && reminderLeadMinutes <= MAX_REMINDER_LEAD_MINUTES,
      `Reminder lead minutes must be between 5 and ${MAX_REMINDER_LEAD_MINUTES}.`
    );
    assert(/^\d{2}:\d{2}$/.test(payload.quietHoursStart), 'Quiet hours start must use HH:MM.');
    assert(/^\d{2}:\d{2}$/.test(payload.quietHoursEnd), 'Quiet hours end must use HH:MM.');
    assert(`${payload.timeZone || ''}`.trim().length > 0, 'Notification time zone is required.');

    const { data, error } = await supabase
      .from('notification_preferences')
      .upsert(
        {
          user_id: userId,
          inbox_enabled: Boolean(payload.inboxEnabled),
          email_enabled: Boolean(payload.emailEnabled),
          reminder_lead_minutes: reminderLeadMinutes,
          quiet_hours_start: payload.quietHoursStart,
          quiet_hours_end: payload.quietHoursEnd,
          time_zone: `${payload.timeZone}`.trim()
        },
        { onConflict: 'user_id' }
      )
      .select('*')
      .maybeSingle();

    if (error) throw error;

    res.status(200).json({
      notificationPreferences: normalizeNotificationPreferences(data)
    });
  } catch (error) {
    const statusCode = Number(error.statusCode || 500);
    res.status(statusCode).json({
      error: 'Failed to save notification preferences',
      details: error.message
    });
  }
};

export const createReminder = async (req, res) => {
  try {
    const userId = req.user.id;
    const payload = normalizeReminderPayload(req.body || {});
    const preferenceResult = await readSingleUserRow({
      table: 'notification_preferences',
      userId
    });
    const normalizedPreferences = normalizeNotificationPreferences(preferenceResult.data);

    assert(payload.title.length > 0, 'Reminder title is required.');
    assert(payload.reminderAt.length > 0, 'Reminder time is required.');
    assert(['inbox', 'email', 'push'].includes(payload.channel), 'Reminder channel is invalid.');
    assert(Number.isFinite(Date.parse(payload.reminderAt)), 'Reminder time is invalid.');
    const reminderTask = await assertOwnedReminderTask({
      userId,
      taskId: payload.taskId,
      taskType: payload.taskType
    });
    await ensureReminderChannelReady({
      userId,
      channel: payload.channel,
      notificationPreferences: normalizedPreferences
    });

    const reminderRow = {
      user_id: userId,
      sub_task_id: reminderTask.type === 'sub_task' ? reminderTask.id : null,
      title: payload.title,
      reminder_at: new Date(payload.reminderAt).toISOString(),
      channel: payload.channel,
      status: 'scheduled',
      payload: {
        task_id: reminderTask.id,
        task_table: reminderTask.table,
        task_type: reminderTask.type
      }
    };

    const { data, error } = await supabase
      .from('reminder_jobs')
      .insert(reminderRow)
      .select('*')
      .single();

    if (error) throw error;

    const { data: delivery } = await supabase
      .from('reminder_deliveries')
      .select('*')
      .eq('reminder_job_id', data.id)
      .eq('channel', data.channel)
      .maybeSingle();

    res.status(201).json({
      reminder: data,
      delivery: delivery || null
    });
  } catch (error) {
    const statusCode = Number(error.statusCode || 500);
    console.error('Reminder Creation Failed:', error.message, 'Payload received:', req.body);
    res.status(statusCode).json({
      error: error.message,
      details: error.message
    });
  }
};

export const updateReminder = async (req, res) => {
  try {
    const userId = req.user.id;
    const reminderId = req.params.id;
    const payload = normalizeReminderActionPayload(req.body || {});

    const { data: reminderJob, error: reminderError } = await supabase
      .from('reminder_jobs')
      .select('*')
      .eq('id', reminderId)
      .eq('user_id', userId)
      .maybeSingle();

    if (reminderError) throw reminderError;
    assert(Boolean(reminderJob), 'Reminder not found.', 404);

    const { data: reminderDelivery, error: deliveryError } = await supabase
      .from('reminder_deliveries')
      .select('*')
      .eq('reminder_job_id', reminderId)
      .eq('channel', reminderJob.channel)
      .maybeSingle();

    if (deliveryError && !isMissingTableError(deliveryError, 'reminder_deliveries')) {
      throw deliveryError;
    }

    const mutation = buildReminderActionMutation({
      reminderJob,
      reminderDelivery: reminderDelivery || null,
      action: payload.action
    });

    const { error: updateError } = await supabase
      .from('reminder_jobs')
      .update({ status: mutation.jobUpdate.status })
      .eq('id', reminderId)
      .eq('user_id', userId);

    if (updateError) throw updateError;

    if (mutation.deliveryUpsert) {
      await upsertReminderDeliveries([mutation.deliveryUpsert]);
    }

    const [{ data: updatedReminder, error: updatedReminderError }, { data: updatedDelivery, error: updatedDeliveryError }] =
      await Promise.all([
        supabase.from('reminder_jobs').select('*').eq('id', reminderId).eq('user_id', userId).maybeSingle(),
        supabase
          .from('reminder_deliveries')
          .select('*')
          .eq('reminder_job_id', reminderId)
          .eq('channel', reminderJob.channel)
          .maybeSingle()
      ]);

    if (updatedReminderError) throw updatedReminderError;
    if (updatedDeliveryError && !isMissingTableError(updatedDeliveryError, 'reminder_deliveries')) {
      throw updatedDeliveryError;
    }

    res.status(200).json({
      reminder: updatedReminder,
      delivery: updatedDelivery || null
    });
  } catch (error) {
    const statusCode = Number(error.statusCode || 500);
    res.status(statusCode).json({
      error: 'Failed to update reminder',
      details: error.message
    });
  }
};

export const upsertPushSubscription = async (req, res) => {
  try {
    const userId = req.user.id;
    const payload = normalizePushSubscriptionPayload(req.body || {});

    assert(payload.endpoint.length > 0, 'Push endpoint is required.');
    assert(payload.provider === 'web', 'Push provider is invalid.');
    assert(payload.p256dh.length > 0, 'Push key p256dh is required.');
    assert(payload.auth.length > 0, 'Push auth key is required.');
    assert(
      payload.expirationTime == null || Number.isFinite(payload.expirationTime),
      'Push expiration time must be numeric when provided.'
    );

    const { data: existingSubscription, error: existingSubscriptionError } = await supabase
      .from('web_push_subscriptions')
      .select('user_id')
      .eq('endpoint', payload.endpoint)
      .maybeSingle();

    if (existingSubscriptionError) throw existingSubscriptionError;
    if (existingSubscription?.user_id && existingSubscription.user_id !== userId) {
      const error = new Error('Push endpoint already belongs to another user.');
      error.statusCode = 403;
      throw error;
    }

    const { data, error } = await supabase
      .from('web_push_subscriptions')
      .upsert(
        {
          user_id: userId,
          provider: payload.provider,
          endpoint: payload.endpoint,
          p256dh: payload.p256dh,
          auth: payload.auth,
          device_platform: payload.devicePlatform || null,
          user_agent: req.get('user-agent') || null
        },
        { onConflict: 'endpoint' }
      )
      .select('*')
      .maybeSingle();

    if (error) throw error;

    res.status(200).json({
      pushSubscription: data
    });
  } catch (error) {
    const statusCode = Number(error.statusCode || 500);
    res.status(statusCode).json({
      error: 'Failed to save push subscription',
      details: error.message
    });
  }
};

export const deletePushSubscription = async (req, res) => {
  try {
    const userId = req.user.id;
    const payload = normalizePushSubscriptionPayload(req.body || {});

    assert(payload.endpoint.length > 0, 'Push endpoint is required.');

    const { error } = await supabase
      .from('web_push_subscriptions')
      .delete()
      .eq('user_id', userId)
      .eq('endpoint', payload.endpoint);

    if (error) throw error;

    res.status(200).json({
      ok: true
    });
  } catch (error) {
    const statusCode = Number(error.statusCode || 500);
    res.status(statusCode).json({
      error: 'Failed to delete push subscription',
      details: error.message
    });
  }
};
