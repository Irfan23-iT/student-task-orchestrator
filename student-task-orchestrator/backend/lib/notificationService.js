import { supabase } from '../config/supabase.js';
import { log } from './logger.js';
import { planReminderDispatch } from './analyticsNotifications.js';
import { isMissingTableError } from './tableErrors.js';

const LOOP_TICK_MS = 60 * 1000;
const DISPATCH_BATCH_SIZE = 100;

let notificationLoopHandle = null;

const isMissingConflictConstraintError = (error) => {
  const message = `${error?.message || error?.details || ''}`.toLowerCase();
  return message.includes('there is no unique or exclusion constraint matching the on conflict specification');
};

const hasEmailWebhook = () => Boolean(process.env.NOTIFICATION_EMAIL_WEBHOOK_URL);
const hasPushWebhook = () => Boolean(process.env.NOTIFICATION_PUSH_WEBHOOK_URL);
const hasResendConfig = () => Boolean(process.env.RESEND_API_KEY);
const hasVapidConfig = () => Boolean(process.env.VAPID_PUBLIC_KEY && process.env.VAPID_PRIVATE_KEY);
const getResendApiKey = () => process.env.RESEND_API_KEY;
const getResendFromEmail = () => process.env.RESEND_FROM_EMAIL || 'onboarding@resend.dev';

export const getNotificationDeliveryCapabilities = () => ({
  inboxConfigured: true,
  emailConfigured: hasEmailWebhook() || hasResendConfig(),
  serverPushConfigured: hasPushWebhook() || hasVapidConfig()
});

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

const readDueReminderJobs = async (nowIso) => {
  const { data, error } = await supabase
    .from('reminder_jobs')
    .select('*')
    .eq('status', 'scheduled')
    .lte('reminder_at', nowIso)
    .order('reminder_at', { ascending: true })
    .limit(DISPATCH_BATCH_SIZE);

  if (error) throw error;
  return data || [];
};

const readNotificationPreferencesByUserId = async (userIds = []) => {
  if (!userIds.length) return new Map();

  const { data, error } = await supabase
    .from('notification_preferences')
    .select('*')
    .in('user_id', userIds);

  if (error && !isMissingTableError(error, 'notification_preferences')) throw error;

  return new Map((data || []).map((row) => [row.user_id, row]));
};

const readPushSubscriptionsByUserId = async (userIds = []) => {
  if (!userIds.length) return new Map();

  const { data, error } = await supabase
    .from('web_push_subscriptions')
    .select('*')
    .in('user_id', userIds);

  if (error && !isMissingTableError(error, 'web_push_subscriptions')) throw error;

  return (data || []).reduce((map, row) => {
    const current = map.get(row.user_id) || [];
    current.push(row);
    map.set(row.user_id, current);
    return map;
  }, new Map());
};

const readReminderDeliveries = async (reminderJobIds = []) => {
  if (!reminderJobIds.length) return [];

  const { data, error } = await supabase
    .from('reminder_deliveries')
    .select('*')
    .in('reminder_job_id', reminderJobIds);

  if (error && !isMissingTableError(error, 'reminder_deliveries')) throw error;
  return data || [];
};

const readUserEmail = async (userId) => {
  const { data, error } = await supabase.from('users').select('email').eq('id', userId).maybeSingle();
  if (error && !isMissingTableError(error, 'users')) throw error;
  return data?.email || null;
};

const deliverEmailWebhook = async (reminderJob) => {
  const webhookUrl = process.env.NOTIFICATION_EMAIL_WEBHOOK_URL;
  if (!webhookUrl) {
    throw new Error('Email delivery webhook is not configured.');
  }

  const email = await readUserEmail(reminderJob.user_id);
  if (!email) {
    throw new Error('No email address found for this reminder.');
  }

  const response = await fetch(webhookUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      to: email,
      subject: reminderJob.title,
      body: reminderJob.title,
      reminderId: reminderJob.id,
      userId: reminderJob.user_id,
      reminderAt: reminderJob.reminder_at
    })
  });

  if (!response.ok) {
    throw new Error(`Email webhook failed with status ${response.status}.`);
  }

  return {
    mode: 'email-webhook'
  };
};

const deliverEmailViaResend = async (reminderJob) => {
  const resendApiKey = getResendApiKey();
  if (!resendApiKey) {
    throw new Error('Resend API key is not configured.');
  }

  const email = await readUserEmail(reminderJob.user_id);
  if (!email) {
    throw new Error('No email address found for this reminder.');
  }

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${resendApiKey}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: getResendFromEmail(),
      to: [email],
      subject: reminderJob.title,
      text: `Reminder: ${reminderJob.title}`
    })
  });

  if (!response.ok) {
    throw new Error(`Resend API failed with status ${response.status}.`);
  }

  return {
    mode: 'resend-api'
  };
};

const deliverEmail = async (reminderJob) => {
  if (hasEmailWebhook()) {
    return deliverEmailWebhook(reminderJob);
  }

  if (hasResendConfig()) {
    return deliverEmailViaResend(reminderJob);
  }

  throw new Error('Email delivery is not configured.');
};

const deliverPushWebhook = async (reminderJob, pushSubscriptions = []) => {
  const webhookUrl = process.env.NOTIFICATION_PUSH_WEBHOOK_URL;
  if (!webhookUrl) {
    return {
      mode: 'app-polling-fallback'
    };
  }

  const response = await fetch(webhookUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      title: reminderJob.title,
      body: reminderJob.title,
      url: '/analytics',
      reminderId: reminderJob.id,
      userId: reminderJob.user_id,
      reminderAt: reminderJob.reminder_at,
      subscriptions: pushSubscriptions.map((subscription) => ({
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh,
        auth: subscription.auth
      }))
    })
  });

  if (!response.ok) {
    throw new Error(`Push webhook failed with status ${response.status}.`);
  }

  return {
    mode: 'server-push-webhook'
  };
};

const applyJobUpdates = async (jobsToUpdate = []) => {
  if (!jobsToUpdate.length) return;

  await Promise.all(
    jobsToUpdate.map(async (jobUpdate) => {
      const { error } = await supabase
        .from('reminder_jobs')
        .update({ status: jobUpdate.status })
        .eq('id', jobUpdate.id)
        .eq('status', 'scheduled');

      if (error) throw error;
    })
  );
};

export const dispatchDueRemindersOnce = async ({ nowIso = new Date().toISOString() } = {}) => {
  const reminderJobs = await readDueReminderJobs(nowIso);
  if (!reminderJobs.length) {
    return { processed: 0, delivered: 0, failed: 0 };
  }

  const userIds = [...new Set(reminderJobs.map((job) => job.user_id).filter(Boolean))];
  const reminderJobIds = reminderJobs.map((job) => job.id);

  const [notificationPreferencesByUserId, pushSubscriptionsByUserId, reminderDeliveries] = await Promise.all([
    readNotificationPreferencesByUserId(userIds),
    readPushSubscriptionsByUserId(userIds),
    readReminderDeliveries(reminderJobIds)
  ]);

  const dispatchPlan = planReminderDispatch({
    reminderJobs,
    reminderDeliveries,
    notificationPreferencesByUserId,
    pushSubscriptionsByUserId,
    nowIso,
    capabilities: {
      email: hasEmailWebhook() || hasResendConfig()
    }
  });

  const emailJobsById = new Map(
    reminderJobs
      .filter((job) => job.channel === 'email')
      .map((job) => [job.id, job])
  );
  const pushJobsById = new Map(
    reminderJobs
      .filter((job) => job.channel === 'push')
      .map((job) => [job.id, job])
  );
  const jobUpdatesById = new Map(dispatchPlan.jobsToUpdate.map((jobUpdate) => [jobUpdate.id, jobUpdate]));

  const deliveriesToPersist = [];

  for (const delivery of dispatchPlan.deliveriesToUpsert) {
    if (delivery.channel !== 'email' || delivery.delivery_state !== 'sent') {
      if (delivery.channel === 'push' && delivery.delivery_state === 'sent') {
        const reminderJob = pushJobsById.get(delivery.reminder_job_id);
        const pushSubscriptions = reminderJob
          ? pushSubscriptionsByUserId.get(reminderJob.user_id) || []
          : [];

        try {
          const pushResult = reminderJob ? await deliverPushWebhook(reminderJob, pushSubscriptions) : { mode: 'unknown' };
          deliveriesToPersist.push({
            ...delivery,
            payload: {
              ...(delivery.payload || {}),
              deliveryMode: pushResult.mode
            }
          });
        } catch (error) {
          deliveriesToPersist.push({
            ...delivery,
            delivery_state: 'failed',
            delivered_at: null,
            error_message: error.message,
            payload: {
              ...(delivery.payload || {}),
              failureCode: 'push-webhook-failed'
            }
          });
          if (reminderJob) {
            jobUpdatesById.set(reminderJob.id, { id: reminderJob.id, status: 'failed' });
          }
        }
        continue;
      }

      deliveriesToPersist.push(delivery);
      continue;
    }

    const reminderJob = emailJobsById.get(delivery.reminder_job_id);
    if (!reminderJob) {
      deliveriesToPersist.push(delivery);
      continue;
    }

    try {
      const emailResult = await deliverEmail(reminderJob);
      deliveriesToPersist.push({
        ...delivery,
        payload: {
          ...(delivery.payload || {}),
          deliveryMode: emailResult.mode
        }
      });
      jobUpdatesById.set(reminderJob.id, { id: reminderJob.id, status: 'sent' });
    } catch (error) {
      deliveriesToPersist.push({
        ...delivery,
        delivery_state: 'failed',
        delivered_at: null,
        error_message: error.message,
        payload: {
          ...(delivery.payload || {}),
          failureCode: hasEmailWebhook() ? 'email-webhook-failed' : 'resend-api-failed'
        }
      });
      jobUpdatesById.set(reminderJob.id, { id: reminderJob.id, status: 'failed' });
    }
  }

  if (deliveriesToPersist.length) {
    await upsertReminderDeliveries(deliveriesToPersist);
  }

  const jobsToPersist = Array.from(jobUpdatesById.values());
  if (jobsToPersist.length) {
    await applyJobUpdates(jobsToPersist);
  }

  return {
    processed: reminderJobs.length,
    delivered: deliveriesToPersist.filter((delivery) => delivery.delivery_state === 'sent').length,
    failed: deliveriesToPersist.filter((delivery) => delivery.delivery_state === 'failed').length
  };
};

export const startNotificationDispatchLoop = () => {
  if (notificationLoopHandle) {
    return;
  }

  const executeTick = async () => {
    try {
      const result = await dispatchDueRemindersOnce();
      if (result.processed > 0) {
        log('info', 'Reminder dispatch tick complete', result);
      }
    } catch (error) {
      log('warn', 'Reminder dispatch tick failed', { error });
    }
  };

  void executeTick();
  notificationLoopHandle = setInterval(executeTick, LOOP_TICK_MS);

  if (typeof notificationLoopHandle.unref === 'function') {
    notificationLoopHandle.unref();
  }
};
