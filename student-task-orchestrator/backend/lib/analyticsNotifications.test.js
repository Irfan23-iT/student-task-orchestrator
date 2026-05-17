import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildReminderActionMutation,
  isWithinQuietHours,
  normalizePushSubscriptionPayload,
  planReminderDispatch
} from './analyticsNotifications.js';

test('planReminderDispatch promotes due inbox reminders into sent deliveries', () => {
  const nowIso = '2026-04-16T10:00:00.000Z';
  const result = planReminderDispatch({
    reminderJobs: [
      {
        id: 'reminder-1',
        user_id: 'user-1',
        reminder_at: '2026-04-16T09:30:00.000Z',
        channel: 'inbox',
        status: 'scheduled'
      },
      {
        id: 'reminder-2',
        user_id: 'user-1',
        reminder_at: '2026-04-16T11:30:00.000Z',
        channel: 'inbox',
        status: 'scheduled'
      }
    ],
    reminderDeliveries: [],
    notificationPreferencesByUserId: new Map([
      [
        'user-1',
        {
          inboxEnabled: true,
          emailEnabled: false,
          quietHoursStart: '22:00',
          quietHoursEnd: '07:00',
          timeZone: 'UTC'
        }
      ]
    ]),
    nowIso
  });

  assert.equal(result.deliveriesToUpsert.length, 1);
  assert.equal(result.deliveriesToUpsert[0].reminder_job_id, 'reminder-1');
  assert.equal(result.deliveriesToUpsert[0].delivery_state, 'sent');
  assert.deepEqual(result.jobsToUpdate, [{ id: 'reminder-1', status: 'sent' }]);
});

test('planReminderDispatch fails due push reminders with no registered browser subscription', () => {
  const nowIso = '2026-04-16T10:00:00.000Z';
  const result = planReminderDispatch({
    reminderJobs: [
      {
        id: 'reminder-push-1',
        user_id: 'user-1',
        reminder_at: '2026-04-16T09:30:00.000Z',
        channel: 'push',
        status: 'scheduled'
      }
    ],
    reminderDeliveries: [],
    notificationPreferencesByUserId: new Map([
      [
        'user-1',
        {
          inboxEnabled: true,
          emailEnabled: false,
          quietHoursStart: '22:00',
          quietHoursEnd: '07:00',
          timeZone: 'UTC'
        }
      ]
    ]),
    pushSubscriptionsByUserId: new Map(),
    nowIso
  });

  assert.equal(result.deliveriesToUpsert.length, 1);
  assert.equal(result.deliveriesToUpsert[0].delivery_state, 'failed');
  assert.match(result.deliveriesToUpsert[0].error_message, /No browser push subscription/i);
  assert.deepEqual(result.jobsToUpdate, [{ id: 'reminder-push-1', status: 'failed' }]);
});

test('isWithinQuietHours respects per-user time zone windows', () => {
  assert.equal(
    isWithinQuietHours({
      nowIso: '2026-04-16T15:30:00.000Z',
      notificationPreferences: {
        quietHoursStart: '22:00',
        quietHoursEnd: '07:00',
        timeZone: 'Asia/Kuala_Lumpur'
      }
    }),
    true
  );

  assert.equal(
    isWithinQuietHours({
      nowIso: '2026-04-16T01:30:00.000Z',
      notificationPreferences: {
        quietHoursStart: '22:00',
        quietHoursEnd: '07:00',
        timeZone: 'Asia/Kuala_Lumpur'
      }
    }),
    false
  );
});

test('buildReminderActionMutation marks reminder read and preserves delivery timing', () => {
  const nowIso = '2026-04-16T10:15:00.000Z';
  const result = buildReminderActionMutation({
    reminderJob: {
      id: 'reminder-1',
      user_id: 'user-1',
      channel: 'inbox'
    },
    reminderDelivery: {
      delivered_at: '2026-04-16T10:00:00.000Z',
      payload: { source: 'overview-sync' }
    },
    action: 'read',
    nowIso
  });

  assert.deepEqual(result.jobUpdate, {
    id: 'reminder-1',
    status: 'dismissed'
  });
  assert.equal(result.deliveryUpsert.delivery_state, 'read');
  assert.equal(result.deliveryUpsert.delivered_at, '2026-04-16T10:00:00.000Z');
  assert.equal(result.deliveryUpsert.read_at, nowIso);
});

test('normalizePushSubscriptionPayload accepts wrapped PushSubscription JSON', () => {
  const result = normalizePushSubscriptionPayload({
    subscription: {
      endpoint: 'https://push.example/subscription',
      expirationTime: null,
      keys: {
        p256dh: 'p-key',
        auth: 'auth-key'
      }
    }
  });

  assert.deepEqual(result, {
    endpoint: 'https://push.example/subscription',
    p256dh: 'p-key',
    auth: 'auth-key',
    expirationTime: null
  });
});
