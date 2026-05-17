import { supabase } from '../config/supabase.js';

const BADGE_THRESHOLDS = {
  'streak-3': ({ streakCount }) => streakCount >= 3,
  'streak-7': ({ streakCount }) => streakCount >= 7,
  'tasks-10': ({ completionTotal }) => completionTotal >= 10,
  'tasks-25': ({ completionTotal }) => completionTotal >= 25
};

const toUtcDate = (value = new Date().toISOString()) => new Date(value).toISOString().slice(0, 10);

export const buildStreakSnapshot = ({ completionEvents = [], todayIso = toUtcDate() } = {}) => {
  const completedDays = Array.from(
    new Set(
      completionEvents
        .map((event) => `${event.event_day || event.completed_at || event.created_at || ''}`.slice(0, 10))
        .filter(Boolean)
    )
  ).sort();

  const daySet = new Set(completedDays);
  let streakCount = 0;
  let cursor = todayIso;

  while (daySet.has(cursor)) {
    streakCount += 1;
    const previousDay = new Date(`${cursor}T00:00:00.000Z`);
    previousDay.setUTCDate(previousDay.getUTCDate() - 1);
    cursor = previousDay.toISOString().slice(0, 10);
  }

  let longestStreak = 0;
  let runningStreak = 0;
  let previousDayKey = null;

  completedDays.forEach((dayKey) => {
    if (!previousDayKey) {
      runningStreak = 1;
    } else {
      const expectedDay = new Date(`${previousDayKey}T00:00:00.000Z`);
      expectedDay.setUTCDate(expectedDay.getUTCDate() + 1);
      runningStreak = expectedDay.toISOString().slice(0, 10) === dayKey ? runningStreak + 1 : 1;
    }

    previousDayKey = dayKey;
    longestStreak = Math.max(longestStreak, runningStreak);
  });

  return {
    streakCount,
    longestStreak
  };
};

export const resolveEarnedBadgeKeys = ({ completionTotal = 0, streakCount = 0 } = {}) =>
  Object.entries(BADGE_THRESHOLDS)
    .filter(([, predicate]) => predicate({ completionTotal, streakCount }))
    .map(([badgeKey]) => badgeKey);

export const syncEngagementForUser = async (userId, options = {}) => {
  const nowIso = options.nowIso || new Date().toISOString();
  const statDay = toUtcDate(nowIso);

  const [{ data: tasks, error: taskError }, { data: completionEvents, error: eventError }] = await Promise.all([
    supabase
      .from('sub_tasks')
      .select('id, status, estimated_minutes')
      .eq('user_id', userId),
    supabase
      .from('completion_events')
      .select('id, sub_task_id, event_day, completed_at, created_at')
      .eq('user_id', userId)
  ]);

  if (taskError) throw taskError;
  if (eventError) throw eventError;

  const taskRows = tasks || [];
  const completionRows = completionEvents || [];
  const completedTasks = taskRows.filter((task) => task.status === 'completed');
  const completedMinutes = completedTasks.reduce((sum, task) => sum + Number(task.estimated_minutes || 0), 0);

  const { error: dailyStatsError } = await supabase.from('productivity_daily_stats').upsert(
    {
      user_id: userId,
      stat_day: statDay,
      completed_count: completedTasks.length,
      open_count: Math.max(taskRows.length - completedTasks.length, 0),
      completed_minutes: completedMinutes
    },
    { onConflict: 'user_id,stat_day' }
  );

  if (dailyStatsError) throw dailyStatsError;

  const streakSnapshot = buildStreakSnapshot({
    completionEvents: completionRows,
    todayIso: statDay
  });

  const { error: streakError } = await supabase.from('streak_snapshots').upsert(
    {
      user_id: userId,
      streak_day: statDay,
      streak_count: streakSnapshot.streakCount,
      longest_streak: streakSnapshot.longestStreak
    },
    { onConflict: 'user_id,streak_day' }
  );

  if (streakError) throw streakError;

  const earnedBadgeKeys = resolveEarnedBadgeKeys({
    completionTotal: completionRows.length,
    streakCount: streakSnapshot.streakCount
  });

  if (earnedBadgeKeys.length) {
    const { data: badgeRows, error: badgeError } = await supabase
      .from('badges')
      .select('id, badge_key')
      .in('badge_key', earnedBadgeKeys);

    if (badgeError) throw badgeError;

    if ((badgeRows || []).length) {
      const { error: userBadgeError } = await supabase.from('user_badges').upsert(
        badgeRows.map((badge) => ({
          user_id: userId,
          badge_id: badge.id,
          payload: {
            badge_key: badge.badge_key,
            awarded_via: 'task_completion'
          }
        })),
        { onConflict: 'user_id,badge_id' }
      );

      if (userBadgeError) throw userBadgeError;
    }
  }

  return {
    statDay,
    completedCount: completedTasks.length,
    completedMinutes,
    streakCount: streakSnapshot.streakCount,
    longestStreak: streakSnapshot.longestStreak
  };
};
