import test from 'node:test';
import assert from 'node:assert/strict';

import {
  chatWithAi,
  createAiChatResponse,
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
