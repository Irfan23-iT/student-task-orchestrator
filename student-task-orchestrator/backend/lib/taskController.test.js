import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createTask,
  deleteAllTasks,
  deleteSessionTasks,
  deleteTask,
  getPrimaryTasks,
  getTasks
} from '../controllers/taskController.js';

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

const createTaskDeleteMockSupabase = () => {
  const operations = [];
  const state = {
    operations,
    reminderJobs: [
      {
        id: 'job-standard',
        sub_task_id: null,
        payload: { task_id: 'task-1', task_table: 'tasks' }
      },
      {
        id: 'job-sub',
        sub_task_id: 'sub-1',
        payload: { task_id: 'sub-1', task_table: 'sub_tasks' }
      },
      {
        id: 'job-primary',
        sub_task_id: null,
        payload: { task_id: 'primary-1', task_table: 'primary_tasks' }
      },
      {
        id: 'job-other',
        sub_task_id: null,
        payload: { task_id: 'other-task', task_table: 'tasks' }
      }
    ]
  };

  class Query {
    constructor(table) {
      this.table = table;
      this.action = null;
      this.filters = [];
    }

    select(columns) {
      this.action = 'select';
      this.columns = columns;
      return this;
    }

    delete() {
      this.action = 'delete';
      return this;
    }

    update(payload) {
      this.action = 'update';
      this.payload = payload;
      return this;
    }

    eq(column, value) {
      this.filters.push(['eq', column, value]);
      return this;
    }

    in(column, value) {
      this.filters.push(['in', column, value]);
      return this;
    }

    then(resolve, reject) {
      return Promise.resolve(this.execute()).then(resolve, reject);
    }

    maybeSingle() {
      const result = this.execute();
      return Promise.resolve({
        data: result.data?.[0] || null,
        error: result.error
      });
    }

    execute() {
      operations.push({
        table: this.table,
        action: this.action,
        filters: this.filters,
        payload: this.payload
      });

      if (this.action === 'delete' || this.action === 'update') {
        return { data: null, error: null };
      }

      if (this.table === 'reminder_jobs') {
        return { data: state.reminderJobs, error: null };
      }

      if (this.table === 'tasks') {
        return { data: [{ id: 'task-1' }], error: null };
      }

      if (this.table === 'sub_tasks') {
        const primaryFilter = this.filters.find(([kind, column]) => kind === 'in' && column === 'primary_task_id');
        if (primaryFilter) {
          return { data: [{ id: 'sub-1' }], error: null };
        }
        return { data: [], error: null };
      }

      return { data: [], error: null };
    }
  }

  return {
    operations,
    from(table) {
      return new Query(table);
    }
  };
};

const getDeletedReminderJobIds = (operations) =>
  operations
    .filter((operation) => operation.table === 'reminder_jobs' && operation.action === 'delete')
    .flatMap((operation) => {
      const idFilter = operation.filters.find(([kind, column]) => kind === 'in' && column === 'id');
      return idFilter ? idFilter[2] : [];
    });

test('createTask inserts a normalized task through the request-scoped client', async () => {
  let insertedPayload = null;
  const req = {
    user: { id: 'user-1' },
    body: {
      title: 'Read chapter 2',
      description: 'Summarize lecture notes',
      dueDate: '2026-05-07T09:00:00.000Z',
      priorityLevel: 'high'
    },
    supabase: {
      from(table) {
        assert.equal(table, 'tasks');
        return {
          insert(payload) {
            insertedPayload = payload;
            return this;
          },
          select() {
            return this;
          },
          single() {
            return Promise.resolve({
              data: {
                id: 'task-1',
                ...insertedPayload,
                created_at: '2026-05-06T16:00:00.000Z'
              },
              error: null
            });
          }
        };
      }
    }
  };
  const res = createRes();

  await createTask(req, res);

  assert.equal(res.statusCode, 201);
  assert.deepEqual(insertedPayload, {
    user_id: 'user-1',
    title: 'Read chapter 2',
    description: 'Summarize lecture notes',
    due_date: '2026-05-07T09:00:00.000Z',
    priority_level: 'High',
    status: 'TODO',
    task_type: 'general'
  });
  assert.equal(res.body.task.priority_level, 'High');
});

test('createTask maps mobile display status to database status', async () => {
  let insertedPayload = null;
  const req = {
    user: { id: 'user-1' },
    body: {
      title: 'Voice task',
      priorityLevel: 'Medium',
      status: 'Pending'
    },
    supabase: {
      from(table) {
        assert.equal(table, 'tasks');
        return {
          insert(payload) {
            insertedPayload = payload;
            return this;
          },
          select() {
            return this;
          },
          single() {
            return Promise.resolve({
              data: {
                id: 'task-voice',
                ...insertedPayload,
                created_at: '2026-05-06T16:00:00.000Z'
              },
              error: null
            });
          }
        };
      }
    }
  };
  const res = createRes();

  await createTask(req, res);

  assert.equal(res.statusCode, 201);
  assert.equal(insertedPayload.status, 'TODO');
});

test('createTask returns 400 for a missing title', async () => {
  const req = {
    user: { id: 'user-1' },
    body: { description: 'No title' },
    supabase: {
      from() {
        throw new Error('should not touch database');
      }
    }
  };
  const res = createRes();

  await createTask(req, res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'Task title is required.');
});

test('getTasks lists only rows requested for the authenticated user', async () => {
  const eqCalls = [];
  const selectCalls = [];
  const req = {
    user: { id: 'user-1' },
    supabase: {
      from(table) {
        assert.equal(table, 'tasks');
        return {
          select(columns) {
            selectCalls.push(columns);
            return this;
          },
          eq(column, value) {
            eqCalls.push([column, value]);
            return this;
          },
          order() {
            return Promise.resolve({
              data: [
                {
                  id: 'task-1',
                  user_id: 'user-1',
                  title: 'Read chapter 2',
                  priority_level: 'Medium',
                  status: 'pending',
                  task_type: 'assignment',
                  category_id: 'category-1',
                  notes: 'Bring rubric',
                  categories: {
                    id: 'category-1',
                    name: 'Coursework',
                    color_hex: '#2563EB'
                  },
                  created_at: '2026-05-06T16:00:00.000Z'
                }
              ],
              error: null
            });
          }
        };
      }
    }
  };
  const res = createRes();

  await getTasks(req, res);

  assert.equal(res.statusCode, 200);
  assert.deepEqual(eqCalls, [['user_id', 'user-1']]);
  assert.match(selectCalls[0], /categories\(id, name, color_hex\)/);
  assert.equal(res.body.tasks[0].title, 'Read chapter 2');
  assert.equal(res.body.tasks[0].status, 'pending');
  assert.equal(res.body.tasks[0].task_type, 'assignment');
  assert.deepEqual(res.body.tasks[0].category, {
    id: 'category-1',
    name: 'Coursework',
    color_hex: '#2563EB'
  });
});

test('getTasks applies optional due date filters after user scope', async () => {
  const calls = [];
  const req = {
    user: { id: 'user-1' },
    query: {
      startDate: '2026-05-01T00:00:00.000Z',
      endDate: '2026-06-01T00:00:00.000Z'
    },
    supabase: {
      from(table) {
        assert.equal(table, 'tasks');
        return {
          select(columns) {
            calls.push(['select', columns]);
            return this;
          },
          eq(column, value) {
            calls.push(['eq', column, value]);
            return this;
          },
          gte(column, value) {
            calls.push(['gte', column, value]);
            return this;
          },
          lte(column, value) {
            calls.push(['lte', column, value]);
            return this;
          },
          order() {
            calls.push(['order']);
            return Promise.resolve({
              data: [],
              error: null
            });
          }
        };
      }
    }
  };
  const res = createRes();

  await getTasks(req, res);

  assert.equal(res.statusCode, 200);
  assert.match(calls[0][1], /categories\(id, name, color_hex\)/);
  assert.deepEqual(calls, [
    ['select', calls[0][1]],
    ['eq', 'user_id', 'user-1'],
    ['gte', 'due_date', '2026-05-01T00:00:00.000Z'],
    ['lte', 'due_date', '2026-06-01T00:00:00.000Z'],
    ['order']
  ]);
});

test('getPrimaryTasks lists primary task rows for the authenticated user', async () => {
  const calls = [];
  const req = {
    user: { id: 'user-1' },
    query: {
      startDate: '2026-05-01T00:00:00.000Z',
      endDate: '2026-06-01T00:00:00.000Z'
    },
    supabase: {
      from(table) {
        assert.equal(table, 'primary_tasks');
        return {
          select(columns) {
            calls.push(['select', columns]);
            return this;
          },
          eq(column, value) {
            calls.push(['eq', column, value]);
            return this;
          },
          gte(column, value) {
            calls.push(['gte', column, value]);
            return this;
          },
          lte(column, value) {
            calls.push(['lte', column, value]);
            return this;
          },
          order() {
            calls.push(['order']);
            return Promise.resolve({
              data: [
                {
                  id: 'primary-1',
                  user_id: 'user-1',
                  title: 'Research paper',
                  due_date: '2026-05-30',
                  task_type: 'assignment',
                  created_at: '2026-05-06T16:00:00.000Z',
                  categories: {
                    id: 'category-1',
                    name: 'Coursework',
                    color_hex: '#2563EB'
                  }
                }
              ],
              error: null
            });
          }
        };
      }
    }
  };
  const res = createRes();

  await getPrimaryTasks(req, res);

  assert.equal(res.statusCode, 200);
  assert.match(calls[0][1], /categories\(id, name, color_hex\)/);
  assert.deepEqual(calls.slice(1), [
    ['eq', 'user_id', 'user-1'],
    ['gte', 'due_date', '2026-05-01T00:00:00.000Z'],
    ['lte', 'due_date', '2026-06-01T00:00:00.000Z'],
    ['order']
  ]);
  assert.equal(res.body.primaryTasks[0].title, 'Research paper');
});

test('deleteSessionTasks clears reminder deliveries and jobs before deleting selected tasks', async () => {
  const mockSupabase = createTaskDeleteMockSupabase();
  const req = {
    user: { id: 'user-1' },
    body: {
      subTaskIds: ['task-1'],
      primaryTaskIds: ['primary-1']
    },
    supabase: mockSupabase
  };
  const res = createRes();

  await deleteSessionTasks(req, res);

  assert.equal(res.statusCode, 200);
  assert.deepEqual(new Set(getDeletedReminderJobIds(mockSupabase.operations)), new Set([
    'job-standard',
    'job-sub',
    'job-primary'
  ]));

  const firstTaskDeleteIndex = mockSupabase.operations.findIndex(
    (operation) => operation.table === 'tasks' && operation.action === 'delete'
  );
  const firstReminderJobDeleteIndex = mockSupabase.operations.findIndex(
    (operation) => operation.table === 'reminder_jobs' && operation.action === 'delete'
  );
  const firstReminderDeliveryDeleteIndex = mockSupabase.operations.findIndex(
    (operation) => operation.table === 'reminder_deliveries' && operation.action === 'delete'
  );

  assert(firstReminderDeliveryDeleteIndex !== -1);
  assert(firstReminderJobDeleteIndex !== -1);
  assert(firstTaskDeleteIndex !== -1);
  assert(firstReminderDeliveryDeleteIndex < firstReminderJobDeleteIndex);
  assert(firstReminderJobDeleteIndex < firstTaskDeleteIndex);
});

test('deleteTask clears reminders before deleting a standard task by id', async () => {
  const mockSupabase = createTaskDeleteMockSupabase();
  const req = {
    params: { id: 'task-1' },
    user: { id: 'user-1' },
    supabase: mockSupabase
  };
  const res = createRes();

  await deleteTask(req, res);

  assert.equal(res.statusCode, 200);
  assert.deepEqual(getDeletedReminderJobIds(mockSupabase.operations), ['job-standard']);

  const reminderJobDeleteIndex = mockSupabase.operations.findIndex(
    (operation) => operation.table === 'reminder_jobs' && operation.action === 'delete'
  );
  const taskDeleteIndex = mockSupabase.operations.findIndex(
    (operation) => operation.table === 'tasks' && operation.action === 'delete'
  );

  assert(reminderJobDeleteIndex !== -1);
  assert(taskDeleteIndex !== -1);
  assert(reminderJobDeleteIndex < taskDeleteIndex);
});

test('deleteAllTasks clears all user reminders before clearing task tables', async () => {
  const mockSupabase = createTaskDeleteMockSupabase();
  const req = {
    user: { id: 'user-1' },
    body: {},
    supabase: mockSupabase
  };
  const res = createRes();

  await deleteAllTasks(req, res);

  assert.equal(res.statusCode, 200);
  assert.deepEqual(new Set(getDeletedReminderJobIds(mockSupabase.operations)), new Set([
    'job-standard',
    'job-sub',
    'job-primary',
    'job-other'
  ]));

  const reminderJobDeleteIndex = mockSupabase.operations.findIndex(
    (operation) => operation.table === 'reminder_jobs' && operation.action === 'delete'
  );
  const coreTaskDeleteIndex = mockSupabase.operations.findIndex(
    (operation) => operation.table === 'tasks' && operation.action === 'delete'
  );
  const primaryTaskDeleteIndex = mockSupabase.operations.findIndex(
    (operation) => operation.table === 'primary_tasks' && operation.action === 'delete'
  );

  assert(reminderJobDeleteIndex !== -1);
  assert(coreTaskDeleteIndex !== -1);
  assert(primaryTaskDeleteIndex !== -1);
  assert(reminderJobDeleteIndex < coreTaskDeleteIndex);
  assert(reminderJobDeleteIndex < primaryTaskDeleteIndex);
});
