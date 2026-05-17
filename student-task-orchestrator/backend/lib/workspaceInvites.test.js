import test from 'node:test';
import assert from 'node:assert/strict';

import { createInviteCode, createUniqueInviteCode, normalizeInviteCode } from './workspaceInvites.js';

test('normalizeInviteCode uppercases and trims invite codes', () => {
  assert.equal(normalizeInviteCode('  ab-12  '), 'AB-12');
  assert.equal(normalizeInviteCode(null), '');
});

test('createInviteCode returns an uppercase invite code without ambiguous characters', () => {
  const code = createInviteCode(8);
  assert.equal(code.length, 8);
  assert.match(code, /^[A-Z2-9]+$/);
  assert.equal(code.includes('0'), false);
  assert.equal(code.includes('1'), false);
  assert.equal(code.includes('I'), false);
  assert.equal(code.includes('O'), false);
});

test('createUniqueInviteCode retries collisions until a free code is found', async () => {
  const attempts = ['AAAA2222', 'BBBB3333', 'CCCC4444'];
  let index = 0;

  const code = await createUniqueInviteCode(async (candidate) => candidate !== 'CCCC4444', {
    length: 8,
    maxAttempts: 3,
    createCode: () => attempts[index++]
  });

  assert.equal(code, 'CCCC4444');
});
