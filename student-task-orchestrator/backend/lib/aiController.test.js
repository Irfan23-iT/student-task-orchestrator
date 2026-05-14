import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildChatSystemPrompt,
  chatWithAi,
  createVisionParseResponse,
  createTaskFromAiAction,
  createAiChatResponse,
  extractActionDirective,
  extractActionDirectives,
} from '../controllers/aiController.js';

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
  },
});

test('createAiChatResponse passes authenticated task context to the LLM prompt', async () => {
  let capturedSystemInstruction = '';
  let capturedPrompt = '';
  const tasks = [
    {
      id: 'task-1',
      title: 'Submit calculus worksheet',
      description: 'Finish problems 1-12',
      due_date: '2026-05-07T09:00:00.000Z',
      priority_level: 'High',
      status: 'Pending',
    },
  ];

  const payload = await createAiChatResponse({
    message: 'What do I have to do today?',
    tasks,
    now: new Date('2026-05-07T01:00:00.000Z'),
    generateText: async ({ systemInstruction, prompt }) => {
      capturedSystemInstruction = systemInstruction;
      capturedPrompt = prompt;
      return 'You need to submit your calculus worksheet today.';
    },
  });

  assert.equal(
    payload.response,
    'You need to submit your calculus worksheet today.',
  );
  assert.equal(payload.taskCount, 1);
  assert.match(capturedSystemInstruction, /Submit calculus worksheet/);
  assert.match(capturedSystemInstruction, /2026-05-07/);
  assert.match(capturedPrompt, /What do I have to do today\?/);
});

test('buildChatSystemPrompt enforces proactive database actions', () => {
  const prompt = buildChatSystemPrompt([], new Date('2026-05-07T01:00:00.000Z'));

  assert.match(
    prompt,
    /You are an autonomous system that manages a database\. You MUST use the ACTION block to create tasks when requested\./,
  );
  assert.match(prompt, /User: "Create a study task for me"/);
  assert.match(prompt, /AI Response: ACTION: \{"type": "CREATE_TASK"/);
  assert.match(prompt, /User: "yes do that" \(in context of adding a task\)/);
  assert.match(prompt, /autonomous executive assistant with direct database write access/);
  assert.match(prompt, /YOU MUST automatically generate the ACTION JSON block/);
  assert.match(prompt, /upcoming event, exam, class, meeting, deadline/);
  assert.match(prompt, /Forbidden phrases/);
  assert.match(prompt, /Do not ask the user to manually create/);
});

test('createAiChatResponse strips CREATE_TASK action JSON from user-visible text', async () => {
  const payload = await createAiChatResponse({
    message: 'Remind me to buy groceries tomorrow at 5 PM.',
    tasks: [],
    now: new Date('2026-05-07T01:00:00.000Z'),
    generateText: async () =>
      'Done! I added that reminder.\nACTION: {"type":"CREATE_TASK","data":{"title":"Buy groceries","priority":"Medium","due_date":"2026-05-08T17:00:00.000Z"}}',
  });

  assert.equal(payload.response, 'Done! I added that reminder.');
  assert.deepEqual(payload.action, {
    type: 'CREATE_TASK',
    data: {
      title: 'Buy groceries',
      priority: 'Medium',
      due_date: '2026-05-08T17:00:00.000Z',
    },
  });
});

test('extractActionDirective parses nested JSON without leaking the ACTION block', () => {
  const result = extractActionDirective(
    'Done.\nACTION: {"type":"CREATE_TASK","data":{"title":"Read {chapter}","priority":"High","due_date":null}}',
  );

  assert.equal(result.response, 'Done.');
  assert.equal(result.action.data.title, 'Read {chapter}');
});

test('createTaskFromAiAction writes CREATE_TASK actions to Supabase', async () => {
  let capturedInsert = null;
  const createdTask = {
    id: 'task-1',
    user_id: 'user-1',
    title: 'Buy groceries',
    due_date: '2026-05-08T09:00:00.000Z',
    priority_level: 'Medium',
    status: 'Pending',
  };
  const db = {
    from(table) {
      assert.equal(table, 'tasks');
      return {
        insert(payload) {
          capturedInsert = payload;
          return this;
        },
        select() {
          return this;
        },
        single() {
          return Promise.resolve({ data: createdTask, error: null });
        },
      };
    },
  };

  const result = await createTaskFromAiAction({
    db,
    userId: 'user-1',
    action: {
      type: 'CREATE_TASK',
      data: {
        title: 'Buy groceries',
        priority: 'medium',
        due_date: '2026-05-08T09:00:00.000Z',
      },
    },
  });

  assert.deepEqual(capturedInsert, {
    user_id: 'user-1',
    title: 'Buy groceries',
    description: null,
    due_date: '2026-05-08T09:00:00.000Z',
    priority_level: 'Medium',
    status: 'Pending',
  });
  assert.equal(result, createdTask);
});

test('extractActionDirectives parses multiple ACTION blocks', () => {
  const result = extractActionDirectives(
    [
      'ACTION: {"type":"CREATE_TASK","data":{"title":"Quiz 1","due_date":"2026-05-12"}}',
      'ACTION: {"type":"CREATE_PRIMARY_TASK","data":{"title":"Final project","sub_tasks":[{"title":"Draft"},{"title":"Submit"}]}}',
    ].join('\n'),
  );

  assert.equal(result.response, '');
  assert.equal(result.actions.length, 2);
  assert.equal(result.actions[0].data.title, 'Quiz 1');
  assert.equal(result.actions[1].data.sub_tasks.length, 2);
});

test('createVisionParseResponse writes vision actions to primary_tasks and sub_tasks', async () => {
  const inserts = [];
  const db = {
    from(table) {
      return {
        insert(payload) {
          inserts.push({ table, payload });
          this.table = table;
          this.payload = payload;
          return this;
        },
        select() {
          if (this.table === 'sub_tasks') {
            return Promise.resolve({
              data: this.payload.map((row, index) => ({
                id: `sub-${inserts.length}-${index}`,
                ...row,
              })),
              error: null,
            });
          }
          return this;
        },
        single() {
          return Promise.resolve({
            data: {
              id: `primary-${inserts.filter((entry) => entry.table === 'primary_tasks').length}`,
              ...this.payload,
            },
            error: null,
          });
        },
      };
    },
  };

  const payload = await createVisionParseResponse({
    imageBase64: 'ZmFrZQ==',
    mimeType: 'image/jpeg',
    db,
    userId: 'user-1',
    generateText: async () =>
      [
        'ACTION: {"type":"CREATE_TASK","data":{"title":"Read Chapter 4","due_date":"2026-05-12","priority":"Medium","task_type":"assignment"}}',
        'ACTION: {"type":"CREATE_PRIMARY_TASK","data":{"title":"Research paper","due_date":"2026-05-30","task_type":"assignment","sub_tasks":[{"title":"Outline paper","due_date":"2026-05-15"},{"title":"Submit final paper","due_date":"2026-05-30"}]}}',
      ].join('\n'),
  });

  assert.equal(payload.actionsParsed, 2);
  assert.equal(payload.created.length, 2);
  assert.equal(inserts[0].table, 'primary_tasks');
  assert.deepEqual(inserts[0].payload, {
    user_id: 'user-1',
    title: 'Read Chapter 4',
    description: null,
    status: 'pending',
    due_date: '2026-05-12',
    task_type: 'assignment',
    total_subtasks: 1,
  });
  assert.equal(inserts[1].table, 'sub_tasks');
  assert.deepEqual(inserts[1].payload, [
    {
      primary_task_id: 'primary-1',
      user_id: 'user-1',
      title: 'Read Chapter 4',
      due_date: '2026-05-12',
    },
  ]);
  assert.equal(inserts[3].payload[0].primary_task_id, 'primary-2');
  assert.equal(inserts[3].payload[1].title, 'Submit final paper');
  assert.equal(inserts[2].payload.task_type, 'assignment');
});

test('chatWithAi queries tasks through the request-scoped Supabase client and falls back without an API key', async () => {
  const eqCalls = [];
  const neqCalls = [];
  const req = {
    user: { id: 'user-1' },
    body: { message: 'What do I have to do today?' },
    supabase: {
      from(table) {
        assert.equal(table, 'tasks');
        return {
          select() {
            return this;
          },
          eq(column, value) {
            eqCalls.push([column, value]);
            return this;
          },
          neq(column, value) {
            neqCalls.push([column, value]);
            return this;
          },
          order() {
            return this;
          },
          limit() {
            return Promise.resolve({
              data: [
                {
                  id: 'task-1',
                  user_id: 'user-1',
                  title: 'Submit calculus worksheet',
                  due_date: '2026-05-07T09:00:00.000Z',
                  priority_level: 'High',
                  status: 'Pending',
                },
              ],
              error: null,
            });
          },
        };
      },
    },
  };
  const res = createRes();
  const originalApiKey = process.env.GEMINI_API_KEY;
  delete process.env.GEMINI_API_KEY;

  await chatWithAi(req, res);

  if (originalApiKey) {
    process.env.GEMINI_API_KEY = originalApiKey;
  }

  assert.equal(res.statusCode, 200);
  assert.deepEqual(eqCalls, [['user_id', 'user-1']]);
  assert.deepEqual(neqCalls, [['status', 'Completed']]);
  assert.equal(res.body.fallback, true);
  assert.match(res.body.response, /Submit calculus worksheet/);
});

test('chatWithAi returns 400 for an empty message', async () => {
  const req = {
    user: { id: 'user-1' },
    body: { message: '   ' },
    supabase: {
      from() {
        throw new Error('should not touch database');
      },
    },
  };
  const res = createRes();

  await chatWithAi(req, res);

  assert.equal(res.statusCode, 400);
  assert.equal(res.body.error, 'Message is required.');
});
