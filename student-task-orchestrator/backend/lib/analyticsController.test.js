import test from 'node:test';
import assert from 'node:assert/strict';

import { createReminder, getAnalyticsOverview } from '../controllers/analyticsController.js';
import { supabase } from '../config/supabase.js';

const listTables = new Set([
  'completion_events',
  'reminder_jobs',
  'reminder_deliveries',
  'web_push_subscriptions',
  'user_badges',
  'badges',
  'orchestration_runs',
  'sub_tasks'
]);

const singleTables = new Set([
  'notification_preferences',
  'productivity_daily_stats',
  'streak_snapshots'
]);

const createBuilder = (table, orderCalls) => ({
  select() {
    return this;
  },
  eq() {
    return this;
  },
  limit() {
    return this;
  },
  order(column, options = {}) {
    orderCalls.push({ table, column, ascending: options.ascending ?? false });
    return this;
  },
  maybeSingle() {
    return Promise.resolve({ data: null, error: null });
  },
  then(resolve, reject) {
    const data = listTables.has(table) ? [] : singleTables.has(table) ? null : [];
    return Promise.resolve({ data, error: null }).then(resolve, reject);
  }
});

test('getAnalyticsOverview orders sub tasks by created_at to match schema', async () => {
  const originalFrom = supabase.from;
  const orderCalls = [];

  supabase.from = (table) => createBuilder(table, orderCalls);

  const req = {
    user: { id: 'user-1' },
    requestId: 'req-analytics-order'
  };

  const res = {
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
  };

  try {
    await getAnalyticsOverview(req, res);
  } finally {
    supabase.from = originalFrom;
  }

  assert.equal(res.statusCode, 200);
  assert.ok(Array.isArray(res.body?.tasks));

  const subTaskOrder = orderCalls.find((call) => call.table === 'sub_tasks');
  assert.deepEqual(subTaskOrder, {
    table: 'sub_tasks',
    column: 'created_at',
    ascending: false
  });
});

test('createReminder accepts standard task ids', async () => {
  const originalFrom = supabase.from;
  const taskId = 'task-1';
  let insertedReminder = null;
  const queriedTables = [];

  const chain = (table) => ({
    select() {
      return this;
    },
    eq() {
      return this;
    },
    insert(payload) {
      insertedReminder = payload;
      return this;
    },
    maybeSingle() {
      if (table === 'notification_preferences') {
        return Promise.resolve({
          data: { inbox_enabled: true },
          error: null
        });
      }

      if (table === 'tasks') {
        return Promise.resolve({
          data: { id: taskId },
          error: null
        });
      }

      if (table === 'reminder_deliveries') {
        return Promise.resolve({ data: null, error: null });
      }

      return Promise.resolve({ data: null, error: null });
    },
    single() {
      return Promise.resolve({
        data: {
          id: 'reminder-1',
          ...insertedReminder
        },
        error: null
      });
    }
  });

  supabase.from = (table) => {
    queriedTables.push(table);
    return chain(table);
  };

  const req = {
    user: { id: 'user-1' },
    body: {
      taskId,
      taskType: 'task',
      title: 'Read chapter',
      reminderAt: '2026-05-12T08:00:00.000Z',
      channel: 'inbox'
    }
  };
  const res = {
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
  };

  try {
    await createReminder(req, res);
  } finally {
    supabase.from = originalFrom;
  }

  assert.equal(res.statusCode, 201);
  assert.ok(queriedTables.includes('tasks'));
  assert.equal(insertedReminder.sub_task_id, null);
  assert.deepEqual(insertedReminder.payload, {
    task_id: taskId,
    task_table: 'tasks',
    task_type: 'task'
  });
});
