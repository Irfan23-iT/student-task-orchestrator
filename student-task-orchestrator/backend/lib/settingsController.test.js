import test from 'node:test';
import assert from 'node:assert/strict';

import { upsertProfileSettings } from '../controllers/settingsController.js';
import { supabase } from '../config/supabase.js';

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

test('upsertProfileSettings updates full_name when Flutter sends name-only payload', async () => {
  const originalFrom = supabase.from;
  const calls = [];

  supabase.from = (table) => {
    calls.push({ table });

    if (table === 'users') {
      return {
        update(payload) {
          calls.push({ table, update: payload });
          return this;
        },
        eq(column, value) {
          calls.push({ table, eq: [column, value] });
          return this;
        },
        select(columns) {
          calls.push({ table, select: columns });
          return this;
        },
        single() {
          return Promise.resolve({ data: { full_name: 'Ada Student' }, error: null });
        }
      };
    }

    throw new Error(`Unexpected table: ${table}`);
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
  }

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.name, 'Ada Student');
  assert.deepEqual(
    calls.find((call) => call.update)?.update,
    { full_name: 'Ada Student' }
  );
  assert.equal(calls.some((call) => call.table === 'user_profiles'), false);
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
