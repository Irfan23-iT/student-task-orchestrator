import { supabase } from '../config/supabase.js';
import {
  completeCalendarOAuth,
  disconnectCalendarForUser,
  getCalendarCallbackRedirect,
  getCalendarConnectUrl,
  getCalendarStatus,
  rebuildManagedCalendarForUser,
  syncCalendarForUser
} from '../lib/calendarService.js';

const normalizeRows = (rows = []) =>
  rows.map(({ id, day_of_week, start_time, end_time, class_name, class_type, created_at, updated_at }) => ({
    id,
    day_of_week,
    start_time,
    end_time,
    class_name,
    class_type,
    created_at,
    updated_at
  }));

const assert = (condition, message, statusCode = 400) => {
  if (condition) return;
  const error = new Error(message);
  error.statusCode = statusCode;
  throw error;
};

const getErrorStatusCode = (error) => {
  if (Number.isInteger(error?.statusCode)) return error.statusCode;
  if (error?.code === '23514' || error?.code === '22P02') return 400;
  return 500;
};

const normalizeDayOfWeek = (value) => {
  const dayMap = {
    1: 'MON',
    2: 'TUE',
    3: 'WED',
    4: 'THU',
    5: 'FRI',
    6: 'SAT',
    7: 'SUN'
  };
  const normalized = String(value ?? '').trim().toUpperCase();
  return dayMap[normalized] || normalized;
};

const normalizeClassType = (value) => {
  const normalized = String(value ?? 'Lect').trim();
  const compactTypes = {
    lect: 'Lect',
    lecture: 'Lect',
    lab: 'Lab',
    laboratory: 'Lab',
    tut: 'Tut',
    tutorial: 'Tut'
  };

  return compactTypes[normalized.toLowerCase()] || normalized || 'Lect';
};

const normalizeClassPayload = (item = {}) => ({
  day_of_week: normalizeDayOfWeek(item.day_of_week ?? item.dayOfWeek),
  start_time: String(item.start_time ?? item.startTime ?? '').trim(),
  end_time: String(item.end_time ?? item.endTime ?? '').trim(),
  class_name: String(item.class_name ?? item.className ?? '').trim(),
  class_type: normalizeClassType(item.class_type ?? item.classType)
});

export const listFixedClasses = async (req, res) => {
  try {
    const { data, error } = await supabase
      .from('fixed_classes')
      .select('*')
      .eq('user_id', req.user.id)
      .order('day_of_week', { ascending: true })
      .order('start_time', { ascending: true });

    if (error) throw error;

    res.status(200).json({ classes: normalizeRows(data || []) });
  } catch (error) {
    console.error('Fixed Classes Load Failed:', error.message, 'User:', req.user?.id);
    res.status(500).json({
      error: error.message,
      details: error.message
    });
  }
};

export const bulkCreateFixedClasses = async (req, res) => {
  try {
    const classes = Array.isArray(req.body?.classes) ? req.body.classes : [];
    if (classes.length === 0) {
      return res.status(400).json({ error: 'At least one class is required.' });
    }

    const normalizedClasses = classes.map(normalizeClassPayload);
    normalizedClasses.forEach((item, index) => {
      assert(['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'].includes(item.day_of_week), `Class ${index + 1} day_of_week is invalid.`);
      assert(item.start_time.length > 0, `Class ${index + 1} start_time is required.`);
      assert(item.end_time.length > 0, `Class ${index + 1} end_time is required.`);
      assert(item.class_name.length > 0, `Class ${index + 1} class_name is required.`);
    });

    const insertPayload = normalizedClasses.map((item) => ({
      user_id: req.user.id,
      day_of_week: item.day_of_week,
      start_time: item.start_time,
      end_time: item.end_time,
      class_name: item.class_name,
      class_type: item.class_type
    }));

    const { data, error } = await supabase
      .from('fixed_classes')
      .insert(insertPayload)
      .select('*');

    if (error) throw error;

    res.status(201).json({ classes: normalizeRows(data || []) });
  } catch (error) {
    const statusCode = getErrorStatusCode(error);
    console.error('Fixed Class Save Failed:', error.message, 'Payload received:', req.body);
    res.status(statusCode).json({
      error: error.message,
      details: error.message
    });
  }
};

export const getCalendarIntegrationStatus = async (req, res) => {
  try {
    const status = await getCalendarStatus({ userId: req.user.id });
    res.status(200).json(status);
  } catch (error) {
    console.error('Calendar Status Failed:', error.message, 'User:', req.user?.id);
    res.status(500).json({
      error: error.message,
      details: error.message
    });
  }
};

export const getCalendarIntegrationConnectUrl = async (req, res) => {
  try {
    const payload = getCalendarConnectUrl({
      userId: req.user.id,
      requestId: req.requestId
    });
    res.status(200).json(payload);
  } catch (error) {
    res.status(503).json({
      error: 'Calendar integration unavailable',
      details: error.message
    });
  }
};

export const syncCalendarIntegration = async (req, res) => {
  try {
    const status = await syncCalendarForUser({
      userId: req.user.id,
      requestId: req.requestId
    });
    res.status(200).json(status);
  } catch (error) {
    if (error?.message === 'Connect Google Calendar first.') {
      return res.status(400).json({
        error: 'NOT_CONNECTED',
        message: 'Connect Google Calendar first.'
      });
    }

    res.status(500).json({
      error: 'Failed to sync calendar',
      details: error.message
    });
  }
};

export const rebuildManagedCalendar = async (req, res) => {
  try {
    const status = await rebuildManagedCalendarForUser({
      userId: req.user.id,
      requestId: req.requestId
    });
    res.status(200).json(status);
  } catch (error) {
    res.status(500).json({
      error: 'Failed to rebuild managed calendar',
      details: error.message
    });
  }
};

export const disconnectCalendarIntegration = async (req, res) => {
  try {
    const result = await disconnectCalendarForUser({
      userId: req.user.id,
      requestId: req.requestId
    });
    res.status(200).json(result);
  } catch (error) {
    res.status(500).json({
      error: 'Failed to disconnect calendar',
      details: error.message
    });
  }
};

export const completeCalendarOAuthCallback = async (req, res) => {
  const { code, state, error, error_description: errorDescription } = req.query || {};

  if (error) {
    return res.redirect(
      302,
      getCalendarCallbackRedirect('error', errorDescription || String(error))
    );
  }

  if (!code || !state) {
    return res.redirect(302, getCalendarCallbackRedirect('error', 'Missing OAuth callback parameters.'));
  }

  try {
    await completeCalendarOAuth({
      code: String(code),
      state: String(state),
      requestId: req.requestId
    });
    return res
      .status(200)
      .type('html')
      .send(
        '<html><body><h2>Successfully connected to Google Calendar!</h2><p>You can close this window and return to the app.</p></body></html>'
      );
  } catch (callbackError) {
    return res.redirect(302, getCalendarCallbackRedirect('error', callbackError.message));
  }
};
