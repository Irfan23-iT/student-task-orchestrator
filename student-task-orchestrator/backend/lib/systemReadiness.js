import { supabase } from '../config/supabase.js';
import { getCalendarIntegrationCapabilities } from './calendarService.js';
import { getErrorTrackingCapabilities } from './errorTracking.js';
import { getNotificationDeliveryCapabilities } from './notificationService.js';
import { getRedis, getRedisConnectionConfig } from './redis.js';

const HEALTH_TIMEOUT_MS = 2_000;

const withTimeout = async (work, label) => {
  let timeoutHandle = null;

  try {
    return await Promise.race([
      work(),
      new Promise((_, reject) => {
        timeoutHandle = setTimeout(() => {
          reject(new Error(`${label} timed out after ${HEALTH_TIMEOUT_MS}ms.`));
        }, HEALTH_TIMEOUT_MS);
      })
    ]);
  } finally {
    clearTimeout(timeoutHandle);
  }
};

const formatReadinessError = (error) => {
  const message = error?.message || String(error);
  const details = error?.details || error?.cause?.message;

  if (details && !String(details).includes(message)) {
    return `${message} (${details})`;
  }

  return message;
};

const buildCheck = ({ key, label, ok, detail, required }) => ({
  key,
  label,
  ok: Boolean(ok),
  detail: detail || '',
  required: Boolean(required)
});

const GOOGLE_ENV_KEYS = [
  'GOOGLE_CLIENT_ID',
  'GOOGLE_CLIENT_SECRET',
  'GOOGLE_CALENDAR_REDIRECT_URI'
];
const EMAIL_ENV_KEYS = ['NOTIFICATION_EMAIL_WEBHOOK_URL', 'RESEND_API_KEY'];
const PUSH_ENV_KEYS = ['NOTIFICATION_PUSH_WEBHOOK_URL', 'VAPID_PUBLIC_KEY', 'VAPID_PRIVATE_KEY'];
const ERROR_TRACKING_ENV_KEYS = ['ERROR_TRACKING_WEBHOOK_URL'];

const findMissingEnv = (keys = []) => keys.filter((key) => !process.env[key]);

const formatEnvList = (keys = []) => keys.join(', ');

const summarizeReadiness = (checks = []) => {
  const blockers = checks
    .filter((check) => check.required && !check.ok)
    .map((check) => `${check.label}: ${check.detail}`);
  const warnings = checks
    .filter((check) => !check.required && !check.ok)
    .map((check) => `${check.label}: ${check.detail}`);

  let status = 'ready';
  if (blockers.length) {
    status = 'blocked';
  } else if (warnings.length) {
    status = 'degraded';
  }

  const missingEnvVars = [...new Set(checks.flatMap((check) => check.missingEnv || []))];
  const nextSteps = checks
    .filter((check) => !check.ok && check.nextStep)
    .map((check) => check.nextStep);

  return {
    status,
    blockers,
    warnings,
    readyForFullHardening: blockers.length === 0 && warnings.length === 0,
    missingEnvVars,
    nextSteps,
    checks
  };
};

const checkSupabaseHealth = async () => {
  const { error } = await supabase.from('primary_tasks').select('id').limit(1);
  if (error) {
    throw error;
  }
};

const checkRedisHealth = async () => {
  const redis = await getRedis();
  await redis.ping();
};

export const buildSystemReadinessReport = ({
  supabaseReachable = true,
  supabaseError = '',
  redisReachable = true,
  redisError = '',
  calendarConfigured = false,
  emailConfigured = false,
  serverPushConfigured = false,
  errorTrackingConfigured = false,
  redisUrl = getRedisConnectionConfig().url,
  redisUsingDefaultUrl = getRedisConnectionConfig().usingDefaultUrl,
  missingCalendarEnv = findMissingEnv(GOOGLE_ENV_KEYS),
  missingEmailEnv = findMissingEnv(EMAIL_ENV_KEYS),
  missingPushEnv = findMissingEnv(PUSH_ENV_KEYS),
  missingErrorTrackingEnv = findMissingEnv(ERROR_TRACKING_ENV_KEYS)
} = {}) =>
  summarizeReadiness([
    {
      ...buildCheck({
        key: 'supabase',
        label: 'Supabase',
        ok: supabaseReachable,
        detail: supabaseReachable
          ? 'Reachable.'
          : supabaseError
            ? `Backend cannot reach Supabase: ${supabaseError}`
            : 'Backend cannot reach Supabase.',
        required: true
      }),
      nextStep: supabaseReachable ? '' : 'Verify Supabase credentials and reachability from backend.'
    },
    {
      ...buildCheck({
        key: 'redis',
        label: 'Redis Streams',
        ok: redisReachable,
        detail: redisReachable
          ? redisUsingDefaultUrl
            ? `Reachable via default fallback ${redisUrl}.`
            : `Reachable via ${redisUrl}.`
          : redisError
            ? redisUsingDefaultUrl
              ? `Background queues cannot reach Redis at default fallback ${redisUrl}: ${redisError}`
              : `Background queues cannot reach Redis at ${redisUrl}: ${redisError}`
          : redisUsingDefaultUrl
            ? `Background queues cannot reach Redis at default fallback ${redisUrl}.`
            : `Background queues cannot reach Redis at ${redisUrl}.`,
        required: true
      }),
      nextStep: redisReachable
        ? ''
        : redisUsingDefaultUrl
          ? `Start local Redis on ${redisUrl} or set REDIS_URL to the deployed instance.`
          : `Fix REDIS_URL reachability: ${redisUrl}.`
    },
    {
      ...buildCheck({
        key: 'calendar',
        label: 'Google Calendar',
        ok: calendarConfigured,
        detail: calendarConfigured
          ? 'OAuth configured.'
          : `Missing ${formatEnvList(missingCalendarEnv)}.`,
        required: false
      }),
      missingEnv: calendarConfigured ? [] : missingCalendarEnv,
      nextStep: calendarConfigured
        ? ''
        : `Set ${formatEnvList(missingCalendarEnv)} for Google Calendar OAuth.`
    },
    {
      ...buildCheck({
        key: 'email',
        label: 'Email reminders',
        ok: emailConfigured,
        detail: emailConfigured
          ? 'Webhook or Resend delivery configured.'
          : `Missing ${formatEnvList(missingEmailEnv)}.`,
        required: false
      }),
      missingEnv: emailConfigured ? [] : missingEmailEnv,
      nextStep: emailConfigured ? '' : `Set ${formatEnvList(missingEmailEnv)} for reminder email delivery.`
    },
    {
      ...buildCheck({
        key: 'push',
        label: 'Browser push reminders',
        ok: serverPushConfigured,
        detail: serverPushConfigured
          ? 'Webhook or VAPID-backed browser registration configured.'
          : `Missing ${formatEnvList(missingPushEnv)}.`,
        required: false
      }),
      missingEnv: serverPushConfigured ? [] : missingPushEnv,
      nextStep: serverPushConfigured ? '' : `Set ${formatEnvList(missingPushEnv)} for browser push reminder setup.`
    },
    {
      ...buildCheck({
        key: 'errorTracking',
        label: 'Error tracking',
        ok: errorTrackingConfigured,
        detail: errorTrackingConfigured
          ? 'Webhook configured.'
          : `Missing ${formatEnvList(missingErrorTrackingEnv)}.`,
        required: false
      }),
      missingEnv: errorTrackingConfigured ? [] : missingErrorTrackingEnv,
      nextStep: errorTrackingConfigured
        ? ''
        : `Set ${formatEnvList(missingErrorTrackingEnv)} for production error reporting.`
    }
  ]);

export const getSystemReadinessSnapshot = async () => {
  const calendarCapabilities = getCalendarIntegrationCapabilities();
  const notificationCapabilities = getNotificationDeliveryCapabilities();
  const errorTrackingCapabilities = getErrorTrackingCapabilities();
  const redisConfig = getRedisConnectionConfig();
  const missingCalendarEnv = findMissingEnv(GOOGLE_ENV_KEYS);
  const missingEmailEnv = findMissingEnv(EMAIL_ENV_KEYS);
  const missingPushEnv = findMissingEnv(PUSH_ENV_KEYS);
  const missingErrorTrackingEnv = findMissingEnv(ERROR_TRACKING_ENV_KEYS);

  const [supabaseHealth, redisHealth] = await Promise.all([
    withTimeout(async () => {
      await checkSupabaseHealth();
      return { ok: true, error: '' };
    }, 'Supabase health check').catch((error) => ({
      ok: false,
      error: formatReadinessError(error)
    })),
    withTimeout(async () => {
      await checkRedisHealth();
      return { ok: true, error: '' };
    }, 'Redis health check').catch((error) => ({
      ok: false,
      error: formatReadinessError(error)
    }))
  ]);

  return buildSystemReadinessReport({
    supabaseReachable: supabaseHealth.ok,
    supabaseError: supabaseHealth.error,
    redisReachable: redisHealth.ok,
    redisError: redisHealth.error,
    calendarConfigured: calendarCapabilities.configured,
    emailConfigured: notificationCapabilities.emailConfigured,
    serverPushConfigured: notificationCapabilities.serverPushConfigured,
    errorTrackingConfigured: errorTrackingCapabilities.configured,
    redisUrl: redisConfig.url,
    redisUsingDefaultUrl: redisConfig.usingDefaultUrl,
    missingCalendarEnv,
    missingEmailEnv,
    missingPushEnv,
    missingErrorTrackingEnv
  });
};
