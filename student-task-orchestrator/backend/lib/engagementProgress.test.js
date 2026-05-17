import test from 'node:test';
import assert from 'node:assert/strict';

import { buildStreakSnapshot, resolveEarnedBadgeKeys } from './engagementProgress.js';

test('buildStreakSnapshot counts only consecutive days ending today', () => {
  const snapshot = buildStreakSnapshot({
    completionEvents: [
      { event_day: '2026-04-14' },
      { event_day: '2026-04-15' },
      { event_day: '2026-04-16' },
      { event_day: '2026-04-10' },
      { event_day: '2026-04-11' }
    ],
    todayIso: '2026-04-16'
  });

  assert.equal(snapshot.streakCount, 3);
  assert.equal(snapshot.longestStreak, 3);
});

test('resolveEarnedBadgeKeys returns milestone badges for streak and completion totals', () => {
  assert.deepEqual(resolveEarnedBadgeKeys({ completionTotal: 3, streakCount: 1 }), []);
  assert.deepEqual(resolveEarnedBadgeKeys({ completionTotal: 12, streakCount: 3 }), ['streak-3', 'tasks-10']);
  assert.deepEqual(resolveEarnedBadgeKeys({ completionTotal: 25, streakCount: 7 }), [
    'streak-3',
    'streak-7',
    'tasks-10',
    'tasks-25'
  ]);
});
