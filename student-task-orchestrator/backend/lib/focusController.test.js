import test from 'node:test';
import assert from 'node:assert/strict';

import { completeFocusSession } from '../controllers/focusController.js';

const createRes = () => ({
  statusCode: 200,
  body: null,
  status(code) {
    this.statusCode = code;
    return this;
  },
  json(payload) {
    this.body = payload;
    return this;
  }
});

test('completeFocusSession calls atomic RPC scoped to authenticated user', async () => {
  let capturedRpc = null;
  const req = {
    user: { id: 'user-1' },
    body: {
      durationMinutes: 25,
      xp: 7
    },
    supabase: {
      rpc(name, params) {
        capturedRpc = { name, params };
        return Promise.resolve({
          data: {
            sessionId: 'session-1',
            durationMinutes: 25,
            xp: 7,
            streakCount: 3,
            longestStreak: 4
          },
          error: null
        });
      }
    }
  };
  const res = createRes();

  await completeFocusSession(req, res);

  assert.equal(res.statusCode, 200);
  assert.deepEqual(capturedRpc, {
    name: 'complete_focus_session',
    params: {
      p_user_id: 'user-1',
      p_duration_minutes: 25,
      p_xp: 7
    }
  });
  assert.equal(res.body.streakCount, 3);
  assert.equal(res.body.longestStreak, 4);
});

test('completeFocusSession rejects invalid durations before database work', async () => {
  const req = {
    user: { id: 'user-1' },
    body: { durationMinutes: 0 },
    supabase: {
      rpc() {
        throw new Error('should not call rpc');
      }
    }
  };
  const res = createRes();

  await completeFocusSession(req, res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'durationMinutes must be between 1 and 1440.');
});
