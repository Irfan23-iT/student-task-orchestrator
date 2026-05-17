import test from 'node:test';
import assert from 'node:assert/strict';

import { getRedis, resetRedisForTests, setRedisClientFactoryForTests } from './redis.js';

test('getRedis retries with a fresh client after an initial connection failure', async () => {
  let connectAttempts = 0;
  const clients = [];

  setRedisClientFactoryForTests(() => {
    const client = {
      on() {},
      async connect() {
        connectAttempts += 1;
        if (connectAttempts === 1) {
          throw new Error('first connect failed');
        }
      }
    };

    clients.push(client);
    return client;
  });

  await assert.rejects(() => getRedis(), /first connect failed/);

  const recoveredClient = await getRedis();

  assert.equal(connectAttempts, 2);
  assert.equal(clients.length, 2);
  assert.equal(recoveredClient, clients[1]);

  resetRedisForTests();
});
