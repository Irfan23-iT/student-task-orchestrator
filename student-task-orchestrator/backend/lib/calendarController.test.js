import test from 'node:test';
import assert from 'node:assert/strict';

import { bulkCreateFixedClasses } from '../controllers/calendarController.js';
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

test('bulkCreateFixedClasses accepts Flutter camelCase and numeric day payloads', async () => {
  const originalFrom = supabase.from;
  let insertedPayload = null;

  supabase.from = (table) => {
    assert.equal(table, 'fixed_classes');
    return {
      insert(payload) {
        insertedPayload = payload;
        return this;
      },
      select() {
        return Promise.resolve({
          data: [
            {
              id: 'class-1',
              ...insertedPayload[0],
              created_at: '2026-05-06T00:00:00.000Z',
              updated_at: '2026-05-06T00:00:00.000Z'
            }
          ],
          error: null
        });
      }
    };
  };

  const req = {
    user: { id: 'user-1' },
    body: {
      classes: [
        {
          dayOfWeek: 1,
          startTime: '10:00:00',
          endTime: '12:00:00',
          className: 'Operating Systems',
          classType: 'lecture'
        }
      ]
    }
  };
  const res = createRes();

  try {
    await bulkCreateFixedClasses(req, res);
  } finally {
    supabase.from = originalFrom;
  }

  assert.equal(res.statusCode, 201);
  assert.deepEqual(insertedPayload, [
    {
      user_id: 'user-1',
      day_of_week: 'MON',
      start_time: '10:00:00',
      end_time: '12:00:00',
      class_name: 'Operating Systems',
      class_type: 'Lect'
    }
  ]);
});

test('bulkCreateFixedClasses returns 400 for invalid day_of_week', async () => {
  const req = {
    user: { id: 'user-1' },
    body: {
      classes: [
        {
          day_of_week: 'FUNDAY',
          start_time: '10:00:00',
          end_time: '12:00:00',
          class_name: 'Operating Systems'
        }
      ]
    }
  };
  const res = createRes();

  await bulkCreateFixedClasses(req, res);

  assert.equal(res.statusCode, 400);
  assert.match(res.body.error, /day_of_week is invalid/);
});
