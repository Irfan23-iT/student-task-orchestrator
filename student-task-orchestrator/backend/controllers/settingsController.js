import { serviceSupabase, supabase } from '../config/supabase.js';
import { getSystemReadinessSnapshot } from '../lib/systemReadiness.js';

const DEFAULT_PROFILE_SETTINGS = {
  wakeTime: '05:00',
  sleepTime: '23:00',
  breakfastStart: '07:30',
  breakfastEnd: '08:30',
  lunchStart: '12:30',
  lunchEnd: '13:30',
  dinnerStart: '19:00',
  dinnerEnd: '20:00',
  transitBufferMinutes: 30
};

const normalizeTimeInput = (value, fallback) => {
  if (typeof value !== 'string') return fallback;

  const match = value.trim().match(/^(\d{1,2}):(\d{2})/);
  if (!match) return fallback;

  return `${match[1].padStart(2, '0')}:${match[2]}`;
};

const normalizeTransitBuffer = (value) => {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) return DEFAULT_PROFILE_SETTINGS.transitBufferMinutes;
  return parsed;
};

const normalizeProfileSettings = (value = {}) => ({
  wakeTime: normalizeTimeInput(value.wakeTime ?? value.wake_time ?? '', DEFAULT_PROFILE_SETTINGS.wakeTime),
  sleepTime: normalizeTimeInput(value.sleepTime ?? value.sleep_time ?? '', DEFAULT_PROFILE_SETTINGS.sleepTime),
  breakfastStart: normalizeTimeInput(
    value.breakfastStart ?? value.breakfast_start ?? '',
    DEFAULT_PROFILE_SETTINGS.breakfastStart
  ),
  breakfastEnd: normalizeTimeInput(
    value.breakfastEnd ?? value.breakfast_end ?? '',
    DEFAULT_PROFILE_SETTINGS.breakfastEnd
  ),
  lunchStart: normalizeTimeInput(value.lunchStart ?? value.lunch_start ?? '', DEFAULT_PROFILE_SETTINGS.lunchStart),
  lunchEnd: normalizeTimeInput(value.lunchEnd ?? value.lunch_end ?? '', DEFAULT_PROFILE_SETTINGS.lunchEnd),
  dinnerStart: normalizeTimeInput(value.dinnerStart ?? value.dinner_start ?? '', DEFAULT_PROFILE_SETTINGS.dinnerStart),
  dinnerEnd: normalizeTimeInput(value.dinnerEnd ?? value.dinner_end ?? '', DEFAULT_PROFILE_SETTINGS.dinnerEnd),
  transitBufferMinutes: normalizeTransitBuffer(value.transitBufferMinutes ?? value.transit_buffer_minutes)
});

const toProfileSettingsRow = (userId, settings) => ({
  user_id: userId,
  wake_time: settings.wakeTime,
  sleep_time: settings.sleepTime,
  breakfast_start: settings.breakfastStart,
  breakfast_end: settings.breakfastEnd,
  lunch_start: settings.lunchStart,
  lunch_end: settings.lunchEnd,
  dinner_start: settings.dinnerStart,
  dinner_end: settings.dinnerEnd,
  transit_buffer_minutes: settings.transitBufferMinutes
});

const toProfileNameRow = (userId, fullName) => ({
  user_id: userId,
  full_name: fullName
});

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

const pickProfileName = (body = {}) => {
  const value = body.name ?? body.fullName ?? body.full_name ?? body.userName ?? body.user_name ?? body.username;
  if (value == null) return null;

  return String(value).trim();
};

const hasProfileSettingsPayload = (body = {}) => {
  const settingKeys = [
    'wakeTime',
    'wake_time',
    'sleepTime',
    'sleep_time',
    'breakfastStart',
    'breakfast_start',
    'breakfastEnd',
    'breakfast_end',
    'lunchStart',
    'lunch_start',
    'lunchEnd',
    'lunch_end',
    'dinnerStart',
    'dinner_start',
    'dinnerEnd',
    'dinner_end',
    'transitBufferMinutes',
    'transit_buffer_minutes'
  ];

  return settingKeys.some((key) => Object.prototype.hasOwnProperty.call(body, key));
};

export const getProfileSettings = async (req, res) => {
  try {
    const [{ data: settingsData, error: settingsError }, { data: userData, error: userError }] = await Promise.all([
      supabase
      .from('user_profiles')
      .select('*')
      .eq('user_id', req.user.id)
        .maybeSingle(),
      supabase
        .from('users')
        .select('full_name')
        .eq('id', req.user.id)
        .maybeSingle()
    ]);

    if (settingsError) throw settingsError;
    if (userError) throw userError;

    res.status(200).json({
      storageMode: 'remote',
      name: userData?.full_name || '',
      settings: normalizeProfileSettings(settingsData || DEFAULT_PROFILE_SETTINGS)
    });
  } catch (error) {
    console.error('Profile Load Failed:', error.message, 'User:', req.user?.id);
    res.status(500).json({
      error: error.message,
      details: error.message
    });
  }
};

export const upsertProfileSettings = async (req, res) => {
  try {
    const body = req.body || {};
    const profileName = pickProfileName(body);
    const shouldUpdateSettings = hasProfileSettingsPayload(body);
    const shouldUpdateName = profileName != null;

    assert(shouldUpdateSettings || shouldUpdateName, 'Profile update payload must include a name or settings fields.');
    if (shouldUpdateName) {
      assert(profileName.length > 0, 'Profile name is required.');
    }

    let settingsData = null;
    if (shouldUpdateSettings) {
      const settings = normalizeProfileSettings(body);
      const { data, error } = await supabase
        .from('user_profiles')
        .upsert(toProfileSettingsRow(req.user.id, settings), { onConflict: 'user_id' })
        .select('*')
        .single();

      if (error) throw error;
      settingsData = data || settings;
    }

    let userData = null;
    if (shouldUpdateName) {
      const [{ data, error }, { data: profileData, error: profileError }] = await Promise.all([
        serviceSupabase
        .auth
        .admin
        .updateUserById(req.user.id, {
          user_metadata: {
            full_name: profileName
          }
        }),
        serviceSupabase
          .from('user_profiles')
          .upsert(toProfileNameRow(req.user.id, profileName), { onConflict: 'user_id' })
          .select('full_name')
          .single()
      ]);

      if (error) throw error;
      if (profileError) throw profileError;
      userData = data?.user;
      userData.publicProfile = profileData;
    }

    res.status(200).json({
      storageMode: 'remote',
      name: userData?.publicProfile?.full_name ?? userData?.user_metadata?.full_name ?? profileName ?? '',
      settings: normalizeProfileSettings(settingsData || body || DEFAULT_PROFILE_SETTINGS)
    });
  } catch (error) {
    const statusCode = getErrorStatusCode(error);
    console.error('Profile Update Failed:', error.message, 'Payload received:', req.body);
    res.status(statusCode).json({
      error: error.message,
      details: error.message
    });
  }
};

export const getSystemReadiness = async (req, res) => {
  try {
    const readiness = await getSystemReadinessSnapshot();
    res.status(200).json(readiness);
  } catch (error) {
    console.error('Readiness Load Failed:', error.message);
    res.status(500).json({
      error: error.message,
      details: error.message
    });
  }
};
