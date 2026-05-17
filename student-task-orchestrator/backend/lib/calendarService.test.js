import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildManagedEventPayload,
  compressBusyIntervals,
  getCalendarConnectUrl
} from './calendarService.js';

test('compressBusyIntervals merges overlapping and touching ranges', () => {
  const merged = compressBusyIntervals([
    { starts_at: '2026-04-16T09:00:00.000Z', ends_at: '2026-04-16T10:00:00.000Z' },
    { starts_at: '2026-04-16T09:30:00.000Z', ends_at: '2026-04-16T11:00:00.000Z' },
    { starts_at: '2026-04-16T11:00:00.000Z', ends_at: '2026-04-16T11:30:00.000Z' },
    { starts_at: '2026-04-16T13:00:00.000Z', ends_at: '2026-04-16T14:00:00.000Z' }
  ]);

  assert.deepEqual(merged, [
    { starts_at: '2026-04-16T09:00:00.000Z', ends_at: '2026-04-16T11:30:00.000Z' },
    { starts_at: '2026-04-16T13:00:00.000Z', ends_at: '2026-04-16T14:00:00.000Z' }
  ]);
});

test('buildManagedEventPayload maps a scheduled task into a Google event body', () => {
  const payload = buildManagedEventPayload(
    {
      id: 'subtask-1',
      title: 'Revise thermodynamics',
      estimated_minutes: 90,
      scheduled_date: '2026-04-18',
      scheduled_start_time: '09:00:00',
      scheduled_end_time: '10:30:00',
      priority_band: 'high',
      priority_reason: 'Exam in 48h'
    },
    'Asia/Kuala_Lumpur'
  );

  assert.equal(payload.summary, 'Study: Revise thermodynamics');
  assert.equal(payload.start.dateTime, '2026-04-18T09:00:00');
  assert.equal(payload.end.dateTime, '2026-04-18T10:30:00');
  assert.equal(payload.start.timeZone, 'Asia/Kuala_Lumpur');
  assert.match(payload.description, /Exam in 48h/);
  assert.equal(payload.extendedProperties.private.subTaskId, 'subtask-1');
});

test('getCalendarConnectUrl creates a Google OAuth URL with offline access', () => {
  process.env.GOOGLE_CLIENT_ID = 'client-id';
  process.env.GOOGLE_CLIENT_SECRET = 'client-secret';
  process.env.GOOGLE_CALENDAR_REDIRECT_URI = 'http://localhost:5000/api/calendar/oauth/callback';
  process.env.GOOGLE_OAUTH_STATE_SECRET = 'state-secret';

  const { url } = getCalendarConnectUrl({
    userId: 'user-1',
    requestId: 'req-1'
  });

  const parsed = new URL(url);
  assert.equal(parsed.origin, 'https://accounts.google.com');
  assert.equal(parsed.searchParams.get('access_type'), 'offline');
  assert.equal(parsed.searchParams.get('prompt'), 'consent');
  assert.equal(parsed.searchParams.get('client_id'), 'client-id');
  assert.ok(parsed.searchParams.get('state'));
});
