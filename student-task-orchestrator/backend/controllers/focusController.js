import { supabase } from '../config/supabase.js';

const assert = (condition, message, statusCode = 400) => {
  if (condition) return;
  const error = new Error(message);
  error.statusCode = statusCode;
  throw error;
};

const getErrorStatusCode = (error) => {
  if (Number.isInteger(error?.statusCode)) return error.statusCode;
  if (error?.code === '22023' || error?.code === '23514') return 400;
  return 500;
};

const parsePositiveInteger = (value, fallback = 0) => {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
};

export const completeFocusSession = async (req, res) => {
  try {
    const db = req.supabase || supabase;
    const userId = req.user.id;
    const durationMinutes = parsePositiveInteger(
      req.body?.durationMinutes ?? req.body?.duration_minutes,
    );
    const xp = parsePositiveInteger(req.body?.xp, 0);

    assert(durationMinutes > 0 && durationMinutes <= 1440, 'durationMinutes must be between 1 and 1440.');
    assert(xp >= 0, 'xp must be zero or greater.');

    const { data, error } = await db.rpc('complete_focus_session', {
      p_user_id: userId,
      p_duration_minutes: durationMinutes,
      p_xp: xp,
    });

    if (error) throw error;

    res.status(200).json({
      focusSession: data,
      streakCount: Number(data?.streakCount ?? data?.streak_count ?? 0),
      longestStreak: Number(data?.longestStreak ?? data?.longest_streak ?? 0),
    });
  } catch (error) {
    const statusCode = getErrorStatusCode(error);
    console.error('Focus Session Complete Failed:', error.message, 'User:', req.user?.id);
    res.status(statusCode).json({
      error: statusCode === 400 ? error.message : 'Failed to complete focus session.',
      details: error.message,
    });
  }
};
