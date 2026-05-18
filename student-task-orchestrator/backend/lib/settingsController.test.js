import test from 'node:test';
import assert from 'node:assert/strict';

import { upsertProfileSettings } from '../controllers/settingsController.js';
import { serviceSupabase, supabase } from '../config/supabase.js';

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

test('upsertProfileSettings updates auth metadata and public profile when Flutter sends name-only payload', async () => {
  const originalFrom = supabase.from;
  const originalServiceFrom = serviceSupabase.from;
  const originalUpdateUserById = serviceSupabase.auth.admin.updateUserById;
  const calls = [];

  supabase.from = (table) => {
    calls.push({ table });

    throw new Error(`Unexpected table: ${table}`);
  };
  serviceSupabase.auth.admin.updateUserById = (userId, payload) => {
    calls.push({ updateUserById: [userId, payload] });
    return Promise.resolve({
      data: {
        user: {
          user_metadata: {
            full_name: 'Ada Student'
          }
        }
      },
      error: null
    });
  };
  serviceSupabase.from = (table) => {
    calls.push({ table });

    if (table === 'user_profiles') {
      return {
        upsert(payload, options) {
          calls.push({ table, upsert: payload, options });
          return this;
        },
        select(columns) {
          calls.push({ table, select: columns });
          return this;
        },
        single() {
          return Promise.resolve({
            data: {
              full_name: 'Ada Student'
            },
            error: null
          });
        }
      };
    }

    throw new Error(`Unexpected service table: ${table}`);
  };

  const req = {
    user: { id: 'user-1' },
    body: { name: 'Ada Student' }
  };
  const res = createRes();

  try {
    await upsertProfileSettings(req, res);
  } finally {
    supabase.from = originalFrom;
    serviceSupabase.from = originalServiceFrom;
    serviceSupabase.auth.admin.updateUserById = originalUpdateUserById;
  }

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.name, 'Ada Student');
  assert.deepEqual(
    calls.find((call) => call.updateUserById)?.updateUserById,
    [
      'user-1',
      {
        user_metadata: {
          full_name: 'Ada Student'
        }
      }
    ]
  );
  assert.deepEqual(
    calls.find((call) => call.upsert)?.upsert,
    {
      id: 'user-1',
      user_id: 'user-1',
      full_name: 'Ada Student'
    }
  );
  assert.deepEqual(
    calls.find((call) => call.upsert)?.options,
    { onConflict: 'id' }
  );
  assert.equal(calls.some((call) => call.table === 'users'), false);
});

test('upsertProfileSettings returns 400 for an empty profile payload', async () => {
  const req = {
    user: { id: 'user-1' },
    body: {}
  };
  const res = createRes();

  await upsertProfileSettings(req, res);

  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /must include a name or settings fields/);
});
