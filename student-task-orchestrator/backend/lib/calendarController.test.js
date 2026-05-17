import test from 'node:test';
import assert from 'node:assert/strict';

import {
  bulkCreateFixedClasses,
  deleteFixedClass,
  updateFixedClass
} from '../controllers/calendarController.js';
import calendarRoutes from '../routes/calendar.js';
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

test('calendar router exposes DELETE /fixed-classes/:id', () => {
  const routes = calendarRoutes.stack.map((layer) => ({
    path: layer.route?.path,
    methods: layer.route?.methods || {}
  }));

  assert(
    routes.some(
      (route) => route.path === '/fixed-classes/:id' && route.methods.delete
    )
  );
  assert(
    routes.some(
      (route) => route.path === '/fixed-classes/:id' && route.methods.put
    )
  );
});

test('bulkCreateFixedClasses accepts Flutter camelCase and numeric day payloads', async () => {
  const originalFrom = supabase.from;
  let insertedPayload = null;

  supabase.from = (table) => {
    assert.equal(table, 'fixed_classes');
    return {
      action: null,
      insert(payload) {
        this.action = 'insert';
        insertedPayload = payload;
        return this;
      },
      select(columns) {
        this.columns = columns;
        if (this.action === 'insert') {
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
        return this;
      },
      eq() {
        return this;
      },
      lt() {
        return this;
      },
      gt() {
        return this;
      },
      limit() {
        return Promise.resolve({ data: [], error: null });
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

test('bulkCreateFixedClasses checks existing classes for user-scoped time conflicts before insert', async () => {
  const originalFrom = supabase.from;
  const calls = [];
  let insertedPayload = null;

  supabase.from = (table) => {
    assert.equal(table, 'fixed_classes');
    return {
      action: null,
      insert(payload) {
        this.action = 'insert';
        insertedPayload = payload;
        calls.push(['insert', payload]);
        return this;
      },
      select(columns) {
        calls.push(['select', columns]);
        this.columns = columns;
        if (this.action === 'insert') {
          return Promise.resolve({
            data: insertedPayload.map((row, index) => ({
              id: `class-${index + 1}`,
              ...row
            })),
            error: null
          });
        }
        return this;
      },
      eq(column, value) {
        calls.push(['eq', column, value]);
        return this;
      },
      lt(column, value) {
        calls.push(['lt', column, value]);
        return this;
      },
      gt(column, value) {
        calls.push(['gt', column, value]);
        return this;
      },
      limit(value) {
        calls.push(['limit', value]);
        return Promise.resolve({ data: [], error: null });
      }
    };
  };

  const req = {
    user: { id: 'user-1' },
    body: {
      classes: [
        {
          day_of_week: 'MON',
          start_time: '10:00:00',
          end_time: '12:00:00',
          class_name: 'Operating Systems'
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
  assert.deepEqual(calls.slice(0, 7), [
    ['select', 'id'],
    ['eq', 'user_id', 'user-1'],
    ['eq', 'day_of_week', 'MON'],
    ['lt', 'start_time', '12:00:00'],
    ['gt', 'end_time', '10:00:00'],
    ['limit', 1],
    ['insert', insertedPayload]
  ]);
});

test('bulkCreateFixedClasses returns 400 when an existing class overlaps', async () => {
  const originalFrom = supabase.from;
  let attemptedInsert = false;

  supabase.from = (table) => {
    assert.equal(table, 'fixed_classes');
    return {
      select() {
        return this;
      },
      eq() {
        return this;
      },
      lt() {
        return this;
      },
      gt() {
        return this;
      },
      limit() {
        return Promise.resolve({
          data: [{ id: 'existing-class' }],
          error: null
        });
      },
      insert() {
        attemptedInsert = true;
        return this;
      }
    };
  };

  const req = {
    user: { id: 'user-1' },
    body: {
      classes: [
        {
          day_of_week: 'MON',
          start_time: '10:00:00',
          end_time: '12:00:00',
          class_name: 'Operating Systems'
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

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'Time conflict: This overlaps with an existing class.');
  assert.equal(attemptedInsert, false);
});

test('bulkCreateFixedClasses returns 400 when submitted classes overlap each other', async () => {
  const req = {
    user: { id: 'user-1' },
    body: {
      classes: [
        {
          day_of_week: 'MON',
          start_time: '10:00:00',
          end_time: '12:00:00',
          class_name: 'Operating Systems'
        },
        {
          day_of_week: 'MON',
          start_time: '11:30:00',
          end_time: '13:00:00',
          class_name: 'Database Systems'
        }
      ]
    }
  };
  const res = createRes();

  await bulkCreateFixedClasses(req, res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'Time conflict: This overlaps with an existing class.');
});

test('updateFixedClass scopes update by id and user and excludes itself from conflict check', async () => {
  const originalFrom = supabase.from;
  const calls = [];

  supabase.from = (table) => {
    assert.equal(table, 'fixed_classes');
    return {
      action: null,
      select(columns) {
        calls.push(['select', columns]);
        if (this.action === 'update') {
          return this;
        }
        return this;
      },
      update(payload) {
        this.action = 'update';
        calls.push(['update', payload]);
        return this;
      },
      eq(column, value) {
        calls.push(['eq', column, value]);
        return this;
      },
      lt(column, value) {
        calls.push(['lt', column, value]);
        return this;
      },
      gt(column, value) {
        calls.push(['gt', column, value]);
        return this;
      },
      neq(column, value) {
        calls.push(['neq', column, value]);
        return this;
      },
      limit(value) {
        calls.push(['limit', value]);
        return Promise.resolve({ data: [], error: null });
      },
      maybeSingle() {
        calls.push(['maybeSingle']);
        return Promise.resolve({
          data: {
            id: 'class-1',
            user_id: 'user-1',
            day_of_week: 'MON',
            start_time: '10:00:00',
            end_time: '12:00:00',
            class_name: 'Operating Systems',
            class_type: 'Lect'
          },
          error: null
        });
      }
    };
  };

  const req = {
    params: { id: 'class-1' },
    user: { id: 'user-1' },
    body: {
      dayOfWeek: 1,
      startTime: '10:00:00',
      endTime: '12:00:00',
      className: 'Operating Systems',
      classType: 'Lecture'
    }
  };
  const res = createRes();

  try {
    await updateFixedClass(req, res);
  } finally {
    supabase.from = originalFrom;
  }

  assert.equal(res.statusCode, 200);
  assert.deepEqual(calls.slice(0, 7), [
    ['select', 'id'],
    ['eq', 'user_id', 'user-1'],
    ['eq', 'day_of_week', 'MON'],
    ['lt', 'start_time', '12:00:00'],
    ['gt', 'end_time', '10:00:00'],
    ['neq', 'id', 'class-1'],
    ['limit', 1]
  ]);
  assert(calls.some((call) => call[0] === 'update'));
  assert.deepEqual(res.body.class, {
    id: 'class-1',
    day_of_week: 'MON',
    start_time: '10:00:00',
    end_time: '12:00:00',
    class_name: 'Operating Systems',
    class_type: 'Lect',
    created_at: undefined,
    updated_at: undefined
  });
});

test('updateFixedClass returns 400 when updated time overlaps another class', async () => {
  const originalFrom = supabase.from;
  let attemptedUpdate = false;

  supabase.from = (table) => {
    assert.equal(table, 'fixed_classes');
    return {
      select() {
        return this;
      },
      eq() {
        return this;
      },
      lt() {
        return this;
      },
      gt() {
        return this;
      },
      neq() {
        return this;
      },
      limit() {
        return Promise.resolve({
          data: [{ id: 'other-class' }],
          error: null
        });
      },
      update() {
        attemptedUpdate = true;
        return this;
      }
    };
  };

  const req = {
    params: { id: 'class-1' },
    user: { id: 'user-1' },
    body: {
      day_of_week: 'MON',
      start_time: '10:00:00',
      end_time: '12:00:00',
      class_name: 'Operating Systems'
    }
  };
  const res = createRes();

  try {
    await updateFixedClass(req, res);
  } finally {
    supabase.from = originalFrom;
  }

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'Time conflict: This overlaps with an existing class.');
  assert.equal(attemptedUpdate, false);
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

test('deleteFixedClass scopes deletion by id and authenticated user', async () => {
  const originalFrom = supabase.from;
  const calls = [];

  supabase.from = (table) => {
    assert.equal(table, 'fixed_classes');
    return {
      delete() {
        calls.push(['delete']);
        return this;
      },
      eq(column, value) {
        calls.push(['eq', column, value]);
        return this;
      },
      select(columns) {
        calls.push(['select', columns]);
        return this;
      },
      maybeSingle() {
        calls.push(['maybeSingle']);
        return Promise.resolve({
          data: { id: 'class-1' },
          error: null
        });
      }
    };
  };

  const req = {
    params: { id: 'class-1' },
    user: { id: 'user-1' }
  };
  const res = createRes();

  try {
    await deleteFixedClass(req, res);
  } finally {
    supabase.from = originalFrom;
  }

  assert.equal(res.statusCode, 200);
  assert.deepEqual(calls, [
    ['delete'],
    ['eq', 'id', 'class-1'],
    ['eq', 'user_id', 'user-1'],
    ['select', 'id'],
    ['maybeSingle']
  ]);
  assert.deepEqual(res.body, { success: true, id: 'class-1' });
});
