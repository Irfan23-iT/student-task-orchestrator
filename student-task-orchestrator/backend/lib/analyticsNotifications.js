export const DEFAULT_NOTIFICATION_PREFERENCES = {
  inboxEnabled: true,
  emailEnabled: false,
  reminderLeadMinutes: 30,
  quietHoursStart: '22:00',
  quietHoursEnd: '07:00',
  timeZone: 'UTC'
};

export const normalizeNotificationPreferences = (row = null) => ({
  inboxEnabled: row?.inboxEnabled ?? row?.inbox_enabled ?? DEFAULT_NOTIFICATION_PREFERENCES.inboxEnabled,
  emailEnabled: row?.emailEnabled ?? row?.email_enabled ?? DEFAULT_NOTIFICATION_PREFERENCES.emailEnabled,
  reminderLeadMinutes:
    row?.reminderLeadMinutes ?? row?.reminder_lead_minutes ?? DEFAULT_NOTIFICATION_PREFERENCES.reminderLeadMinutes,
  quietHoursStart: row?.quietHoursStart ?? row?.quiet_hours_start ?? DEFAULT_NOTIFICATION_PREFERENCES.quietHoursStart,
  quietHoursEnd: row?.quietHoursEnd ?? row?.quiet_hours_end ?? DEFAULT_NOTIFICATION_PREFERENCES.quietHoursEnd,
  timeZone: row?.timeZone ?? row?.time_zone ?? DEFAULT_NOTIFICATION_PREFERENCES.timeZone
});

export const normalizeReminderPayload = (body = {}) => ({
  title: String(body.title || '').trim(),
  taskId: body.taskId || body.task_id || body.subTaskId || body.sub_task_id || null,
  taskType: String(body.taskType || body.task_type || '').trim().toLowerCase(),
  subTaskId: body.subTaskId || body.sub_task_id || body.taskId || body.task_id || null,
  reminderAt: String(body.reminderAt || body.reminder_at || '').trim(),
  channel: String(body.channel || 'inbox').trim().toLowerCase()
});

export const normalizeReminderActionPayload = (body = {}) => ({
  action: String(body.action || '').trim().toLowerCase()
});

export const normalizePushSubscriptionPayload = (body = {}) => {
  const source = body?.subscription && typeof body.subscription === 'object' ? body.subscription : body;
  const keys = source?.keys || {};

  return {
    endpoint: String(source?.endpoint || '').trim(),
    p256dh: String(keys?.p256dh || source?.p256dh || '').trim(),
    auth: String(keys?.auth || source?.auth || '').trim(),
    expirationTime:
      source?.expirationTime == null || source?.expirationTime === ''
        ? null
        : Number.parseInt(source.expirationTime, 10)
  };
};

const latestDeliveryByKey = (reminderDeliveries = []) => {
  const deliveryMap = new Map();

  reminderDeliveries.forEach((delivery) => {
    const key = `${delivery.reminder_job_id}:${delivery.channel}`;
    const current = deliveryMap.get(key);

    if (!current) {
      deliveryMap.set(key, delivery);
      return;
    }

    const currentStamp = `${current.updated_at || current.created_at || ''}`;
    const nextStamp = `${delivery.updated_at || delivery.created_at || ''}`;
    if (nextStamp >= currentStamp) {
      deliveryMap.set(key, delivery);
    }
  });

  return deliveryMap;
};

const isChannelEnabled = (channel, notificationPreferences) => {
  if (channel === 'inbox') return Boolean(notificationPreferences.inboxEnabled);
  if (channel === 'email') return Boolean(notificationPreferences.emailEnabled);
  return true;
};

const parseClockMinutes = (value) => {
  const match = `${value || ''}`.match(/^(\d{2}):(\d{2})$/);
  if (!match) return null;

  const hours = Number.parseInt(match[1], 10);
  const minutes = Number.parseInt(match[2], 10);
  if (!Number.isFinite(hours) || !Number.isFinite(minutes) || hours > 23 || minutes > 59) {
    return null;
  }

  return hours * 60 + minutes;
};

const resolveTimeZone = (value) => {
  const candidate = `${value || ''}`.trim() || DEFAULT_NOTIFICATION_PREFERENCES.timeZone;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: candidate }).format(new Date());
    return candidate;
  } catch {
    return DEFAULT_NOTIFICATION_PREFERENCES.timeZone;
  }
};

const readLocalClockMinutes = (nowIso, timeZone) => {
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone,
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23'
  });

  const parts = formatter.formatToParts(new Date(nowIso));
  const hour = Number.parseInt(parts.find((part) => part.type === 'hour')?.value || '', 10);
  const minute = Number.parseInt(parts.find((part) => part.type === 'minute')?.value || '', 10);

  if (!Number.isFinite(hour) || !Number.isFinite(minute)) {
    return null;
  }

  return hour * 60 + minute;
};

export const isWithinQuietHours = ({
  nowIso = new Date().toISOString(),
  notificationPreferences = DEFAULT_NOTIFICATION_PREFERENCES
} = {}) => {
  const quietStartMinutes = parseClockMinutes(notificationPreferences?.quietHoursStart);
  const quietEndMinutes = parseClockMinutes(notificationPreferences?.quietHoursEnd);

  if (quietStartMinutes == null || quietEndMinutes == null || quietStartMinutes === quietEndMinutes) {
    return false;
  }

  const clockMinutes = readLocalClockMinutes(nowIso, resolveTimeZone(notificationPreferences?.timeZone));
  if (clockMinutes == null) {
    return false;
  }

  if (quietStartMinutes < quietEndMinutes) {
    return clockMinutes >= quietStartMinutes && clockMinutes < quietEndMinutes;
  }

  return clockMinutes >= quietStartMinutes || clockMinutes < quietEndMinutes;
};

const buildDeliveryRecord = ({
  reminderJob,
  reminderDelivery = null,
  deliveryState,
  nowIso,
  errorMessage = null,
  payload = {}
}) => ({
  user_id: reminderJob.user_id,
  reminder_job_id: reminderJob.id,
  channel: reminderJob.channel,
  delivery_state: deliveryState,
  delivered_at:
    deliveryState === 'failed'
      ? reminderDelivery?.delivered_at || null
      : reminderDelivery?.delivered_at || nowIso,
  read_at: reminderDelivery?.read_at || null,
  error_message: errorMessage,
  payload: {
    ...(reminderDelivery?.payload || {}),
    ...payload
  }
});

export const planReminderDispatch = ({
  reminderJobs = [],
  reminderDeliveries = [],
  notificationPreferencesByUserId = new Map(),
  pushSubscriptionsByUserId = new Map(),
  nowIso = new Date().toISOString(),
  capabilities = {
    email: false
  }
} = {}) => {
  const deliveryMap = latestDeliveryByKey(reminderDeliveries);
  const deliveriesToUpsert = [];
  const jobsToUpdate = [];

  reminderJobs.forEach((job) => {
    if (!job?.id || !job?.user_id || !job?.reminder_at) return;
    if (`${job.status || ''}`.toLowerCase() !== 'scheduled') return;

    const reminderAt = Date.parse(job.reminder_at);
    const now = Date.parse(nowIso);
    if (!Number.isFinite(reminderAt) || !Number.isFinite(now) || reminderAt > now) return;

    const notificationPreferences =
      notificationPreferencesByUserId.get(job.user_id) || DEFAULT_NOTIFICATION_PREFERENCES;
    if (isWithinQuietHours({ nowIso, notificationPreferences })) return;

    const key = `${job.id}:${job.channel}`;
    const existingDelivery = deliveryMap.get(key);
    const deliveryState = `${existingDelivery?.delivery_state || ''}`.toLowerCase();

    if (deliveryState === 'read' || deliveryState === 'sent') {
      jobsToUpdate.push({ id: job.id, status: 'sent' });
      return;
    }

    if (!isChannelEnabled(job.channel, notificationPreferences)) {
      deliveriesToUpsert.push(
        buildDeliveryRecord({
          reminderJob: job,
          reminderDelivery: existingDelivery,
          deliveryState: 'failed',
          nowIso,
          errorMessage: 'Notification channel is disabled in preferences.',
          payload: {
            source: 'dispatch-loop',
            failureCode: 'channel-disabled'
          }
        })
      );
      jobsToUpdate.push({ id: job.id, status: 'failed' });
      return;
    }

    if (job.channel === 'email' && !capabilities.email) {
      deliveriesToUpsert.push(
        buildDeliveryRecord({
          reminderJob: job,
          reminderDelivery: existingDelivery,
          deliveryState: 'failed',
          nowIso,
          errorMessage: 'Email delivery is not configured.',
          payload: {
            source: 'dispatch-loop',
            failureCode: 'email-not-configured'
          }
        })
      );
      jobsToUpdate.push({ id: job.id, status: 'failed' });
      return;
    }

    if (job.channel === 'push') {
      const pushSubscriptions = pushSubscriptionsByUserId.get(job.user_id) || [];
      if (!pushSubscriptions.length) {
        deliveriesToUpsert.push(
          buildDeliveryRecord({
            reminderJob: job,
            reminderDelivery: existingDelivery,
            deliveryState: 'failed',
            nowIso,
            errorMessage: 'No browser push subscription is registered.',
            payload: {
              source: 'dispatch-loop',
              failureCode: 'missing-push-subscription'
            }
          })
        );
        jobsToUpdate.push({ id: job.id, status: 'failed' });
        return;
      }
    }

    deliveriesToUpsert.push(
      buildDeliveryRecord({
        reminderJob: job,
        reminderDelivery: existingDelivery,
        deliveryState: 'sent',
        nowIso,
        payload: {
          source: 'dispatch-loop'
        }
      })
    );
    jobsToUpdate.push({ id: job.id, status: 'sent' });
  });

  return {
    deliveriesToUpsert,
    jobsToUpdate
  };
};

export const buildReminderActionMutation = ({
  reminderJob,
  reminderDelivery = null,
  action,
  nowIso = new Date().toISOString()
}) => {
  if (!reminderJob?.id) {
    throw new Error('Reminder job is required.');
  }

  if (action === 'read') {
    return {
      jobUpdate: {
        id: reminderJob.id,
        status: 'dismissed'
      },
      deliveryUpsert: {
        user_id: reminderJob.user_id,
        reminder_job_id: reminderJob.id,
        channel: reminderJob.channel,
        delivery_state: 'read',
        delivered_at: reminderDelivery?.delivered_at || nowIso,
        read_at: nowIso,
        error_message: null,
        payload: {
          ...(reminderDelivery?.payload || {}),
          source: 'user-read'
        }
      }
    };
  }

  if (action === 'cancel') {
    return {
      jobUpdate: {
        id: reminderJob.id,
        status: 'cancelled'
      },
      deliveryUpsert: null
    };
  }

  throw new Error('Reminder action is invalid.');
};
