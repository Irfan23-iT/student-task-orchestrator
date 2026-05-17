import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildOperationsMetricsSnapshot,
  recordHttpRequest,
  recordQueuePublish,
  resetOperationalMetricsForTests
} from './operationsMetrics.js';

test('buildOperationsMetricsSnapshot includes HTTP, queue, and DLQ counters', () => {
  resetOperationalMetricsForTests();

  recordHttpRequest({ method: 'GET', statusCode: 200 });
  recordHttpRequest({ method: 'POST', statusCode: 503 });
  recordQueuePublish({ stream: 'jobs:orchestration', success: true });
  recordQueuePublish({ stream: 'jobs:orchestration', success: false });

  const snapshot = buildOperationsMetricsSnapshot({
    redisReachable: true,
    streamDepths: {
      'jobs:orchestration': 3,
      'jobs:dlq': 1
    },
    redisUrl: 'redis://cache.internal:6379',
    redisUsingDefaultUrl: false
  });

  assert.equal(snapshot.redis.reachable, true);
  assert.equal(snapshot.http.total, 2);
  assert.equal(snapshot.http.byMethod.GET, 1);
  assert.equal(snapshot.http.byMethod.POST, 1);
  assert.equal(snapshot.http.byStatusFamily['2xx'], 1);
  assert.equal(snapshot.http.byStatusFamily['5xx'], 1);
  assert.equal(snapshot.queue.published['jobs:orchestration'], 1);
  assert.equal(snapshot.queue.failed['jobs:orchestration'], 1);
  assert.equal(
    snapshot.queue.streams.find((stream) => stream.name === 'jobs:orchestration')?.depth,
    3
  );
  assert.equal(snapshot.dlq.depth, 1);
});
