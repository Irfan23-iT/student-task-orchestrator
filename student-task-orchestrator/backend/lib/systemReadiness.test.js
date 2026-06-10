import test from 'node:test';
import assert from 'node:assert/strict';

import { buildSystemReadinessReport } from './systemReadiness.js';

test('buildSystemReadinessReport marks rollout blocked when core services fail', () => {
  const report = buildSystemReadinessReport({
    supabaseReachable: true,
    redisReachable: false,
    calendarConfigured: true,
    driveConfigured: true,
    emailConfigured: true,
    serverPushConfigured: true,
    errorTrackingConfigured: true,
    redisUrl: 'redis://127.0.0.1:6379',
    redisUsingDefaultUrl: true
  });

  assert.equal(report.status, 'blocked');
  assert.equal(report.readyForFullHardening, false);
  assert.equal(report.blockers.length, 1);
  assert.match(report.blockers[0], /Redis Streams/i);
  assert.match(report.nextSteps[0], /REDIS_URL|Start local Redis/i);
});

test('buildSystemReadinessReport marks rollout degraded when optional integrations are missing', () => {
  const report = buildSystemReadinessReport({
    supabaseReachable: true,
    redisReachable: true,
    calendarConfigured: false,
    driveConfigured: false,
    emailConfigured: false,
    serverPushConfigured: false,
    errorTrackingConfigured: false,
    missingCalendarEnv: ['GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_SECRET', 'GOOGLE_CALENDAR_REDIRECT_URI'],
    missingDriveEnv: ['GOOGLE_DRIVE_REDIRECT_URI'],
    missingEmailEnv: ['NOTIFICATION_EMAIL_WEBHOOK_URL', 'RESEND_API_KEY'],
    missingPushEnv: ['NOTIFICATION_PUSH_WEBHOOK_URL', 'VAPID_PUBLIC_KEY', 'VAPID_PRIVATE_KEY'],
    missingErrorTrackingEnv: ['ERROR_TRACKING_WEBHOOK_URL']
  });

  assert.equal(report.status, 'degraded');
  assert.equal(report.blockers.length, 0);
  assert.equal(report.warnings.length, 5);
  assert.equal(report.readyForFullHardening, false);
  assert.deepEqual(report.missingEnvVars, [
    'GOOGLE_CLIENT_ID',
    'GOOGLE_CLIENT_SECRET',
    'GOOGLE_CALENDAR_REDIRECT_URI',
    'GOOGLE_DRIVE_REDIRECT_URI',
    'NOTIFICATION_EMAIL_WEBHOOK_URL',
    'RESEND_API_KEY',
    'NOTIFICATION_PUSH_WEBHOOK_URL',
    'VAPID_PUBLIC_KEY',
    'VAPID_PRIVATE_KEY',
    'ERROR_TRACKING_WEBHOOK_URL'
  ]);
});

test('buildSystemReadinessReport marks rollout ready when all checks pass', () => {
  const report = buildSystemReadinessReport({
    supabaseReachable: true,
    redisReachable: true,
    calendarConfigured: true,
    driveConfigured: true,
    emailConfigured: true,
    serverPushConfigured: true,
    errorTrackingConfigured: true,
    redisUrl: 'redis://cache.internal:6379',
    redisUsingDefaultUrl: false,
    missingCalendarEnv: [],
    missingDriveEnv: [],
    missingEmailEnv: [],
    missingPushEnv: [],
    missingErrorTrackingEnv: []
  });

  assert.equal(report.status, 'ready');
  assert.deepEqual(report.blockers, []);
  assert.deepEqual(report.warnings, []);
  assert.equal(report.readyForFullHardening, true);
  assert.deepEqual(report.missingEnvVars, []);
  assert.deepEqual(report.nextSteps, []);
});
