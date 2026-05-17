import test from 'node:test';
import assert from 'node:assert/strict';

import { getNotificationDeliveryCapabilities } from './notificationService.js';

test('getNotificationDeliveryCapabilities reflects configured webhook env flags', () => {
  const previousEmailWebhook = process.env.NOTIFICATION_EMAIL_WEBHOOK_URL;
  const previousPushWebhook = process.env.NOTIFICATION_PUSH_WEBHOOK_URL;

  process.env.NOTIFICATION_EMAIL_WEBHOOK_URL = 'https://notify.example/email';
  process.env.NOTIFICATION_PUSH_WEBHOOK_URL = 'https://notify.example/push';

  try {
    assert.deepEqual(getNotificationDeliveryCapabilities(), {
      inboxConfigured: true,
      emailConfigured: true,
      serverPushConfigured: true
    });
  } finally {
    if (previousEmailWebhook == null) {
      delete process.env.NOTIFICATION_EMAIL_WEBHOOK_URL;
    } else {
      process.env.NOTIFICATION_EMAIL_WEBHOOK_URL = previousEmailWebhook;
    }

    if (previousPushWebhook == null) {
      delete process.env.NOTIFICATION_PUSH_WEBHOOK_URL;
    } else {
      process.env.NOTIFICATION_PUSH_WEBHOOK_URL = previousPushWebhook;
    }
  }
});

test('getNotificationDeliveryCapabilities reflects resend and vapid env flags', () => {
  const previousEmailWebhook = process.env.NOTIFICATION_EMAIL_WEBHOOK_URL;
  const previousPushWebhook = process.env.NOTIFICATION_PUSH_WEBHOOK_URL;
  const previousResendApiKey = process.env.RESEND_API_KEY;
  const previousVapidPublicKey = process.env.VAPID_PUBLIC_KEY;
  const previousVapidPrivateKey = process.env.VAPID_PRIVATE_KEY;

  delete process.env.NOTIFICATION_EMAIL_WEBHOOK_URL;
  delete process.env.NOTIFICATION_PUSH_WEBHOOK_URL;
  process.env.RESEND_API_KEY = 're_example';
  process.env.VAPID_PUBLIC_KEY = 'public';
  process.env.VAPID_PRIVATE_KEY = 'private';

  try {
    assert.deepEqual(getNotificationDeliveryCapabilities(), {
      inboxConfigured: true,
      emailConfigured: true,
      serverPushConfigured: true
    });
  } finally {
    if (previousEmailWebhook == null) {
      delete process.env.NOTIFICATION_EMAIL_WEBHOOK_URL;
    } else {
      process.env.NOTIFICATION_EMAIL_WEBHOOK_URL = previousEmailWebhook;
    }

    if (previousPushWebhook == null) {
      delete process.env.NOTIFICATION_PUSH_WEBHOOK_URL;
    } else {
      process.env.NOTIFICATION_PUSH_WEBHOOK_URL = previousPushWebhook;
    }

    if (previousResendApiKey == null) {
      delete process.env.RESEND_API_KEY;
    } else {
      process.env.RESEND_API_KEY = previousResendApiKey;
    }

    if (previousVapidPublicKey == null) {
      delete process.env.VAPID_PUBLIC_KEY;
    } else {
      process.env.VAPID_PUBLIC_KEY = previousVapidPublicKey;
    }

    if (previousVapidPrivateKey == null) {
      delete process.env.VAPID_PRIVATE_KEY;
    } else {
      process.env.VAPID_PRIVATE_KEY = previousVapidPrivateKey;
    }
  }
});
