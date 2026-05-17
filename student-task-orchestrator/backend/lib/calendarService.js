import crypto from 'node:crypto';

import { supabase } from '../config/supabase.js';
import { log } from './logger.js';

const GOOGLE_OAUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth';
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GOOGLE_CALENDAR_API_BASE = 'https://www.googleapis.com/calendar/v3';
const GOOGLE_CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar';
const SYNC_WINDOW_DAYS = 14;
const SYNC_INTERVAL_MS = 4 * 60 * 60 * 1000;
const LOOP_TICK_MS = 60 * 1000;
const REFRESH_SKEW_MS = 5 * 60 * 1000;
const OAUTH_STATE_TTL_MS = 30 * 60 * 1000;
const MANAGED_EVENT_SOURCE = 'student-task-orchestrator';
const MERGED_CALENDAR_ID = '__merged__';

let calendarLoopHandle = null;
let lastPruneStamp = '';

const base64UrlEncode = (value) => Buffer.from(value, 'utf8').toString('base64url');
const base64UrlDecode = (value) => Buffer.from(value, 'base64url').toString('utf8');

const getRequestId = (requestId) => requestId || crypto.randomUUID();
const getGoogleClientId = () => process.env.GOOGLE_CLIENT_ID || '';
const getGoogleClientSecret = () => process.env.GOOGLE_CLIENT_SECRET || '';
const getGoogleRedirectUri = () => process.env.GOOGLE_CALENDAR_REDIRECT_URI || '';
const getFrontendBaseUrl = () => (process.env.FRONTEND_BASE_URL || 'http://localhost:5173').replace(/\/+$/, '');
const getFallbackTimezone = () => process.env.APP_TIMEZONE || 'UTC';

const hasCalendarConfig = () => Boolean(getGoogleClientId() && getGoogleClientSecret() && getGoogleRedirectUri());

export const getCalendarIntegrationCapabilities = () => ({
  configured: hasCalendarConfig()
});

const ensureCalendarConfig = () => {
  if (!hasCalendarConfig()) {
    throw new Error('Google Calendar OAuth is not configured.');
  }
};

const getStateSecret = () =>
  process.env.GOOGLE_OAUTH_STATE_SECRET || process.env.SUPABASE_SERVICE_ROLE_KEY || 'calendar-state-secret';

const buildCallbackRedirect = (status, message = '') => {
  const params = new URLSearchParams({ calendar: status });
  if (message) {
    params.set('message', message);
  }
  return `${getFrontendBaseUrl()}/settings?${params.toString()}`;
};

const decodeJwtPayload = (jwt) => {
  if (!jwt || typeof jwt !== 'string') return {};
  const parts = jwt.split('.');
  if (parts.length < 2) return {};
  try {
    return JSON.parse(base64UrlDecode(parts[1]));
  } catch {
    return {};
  }
};

const parseResponsePayload = async (response) => {
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.toLowerCase().includes('application/json')) {
    return null;
  }

  try {
    return await response.json();
  } catch {
    return null;
  }
};

const throwGoogleError = async (response, fallbackMessage) => {
  const payload = await parseResponsePayload(response);
  const error = new Error(payload?.error_description || payload?.error?.message || fallbackMessage);
  error.status = response.status;
  error.payload = payload;
  throw error;
};

const buildOAuthState = ({ userId, requestId }) => {
  const payload = base64UrlEncode(
    JSON.stringify({
      userId,
      requestId: getRequestId(requestId),
      issuedAt: Date.now(),
      nonce: crypto.randomUUID()
    })
  );

  const signature = crypto.createHmac('sha256', getStateSecret()).update(payload).digest('base64url');
  return `${payload}.${signature}`;
};

const parseOAuthState = (state) => {
  if (!state || !state.includes('.')) {
    throw new Error('Invalid OAuth state.');
  }

  const [payload, providedSignature] = state.split('.');
  const expectedSignature = crypto.createHmac('sha256', getStateSecret()).update(payload).digest('base64url');

  if (
    providedSignature.length !== expectedSignature.length ||
    !crypto.timingSafeEqual(Buffer.from(providedSignature), Buffer.from(expectedSignature))
  ) {
    throw new Error('OAuth state verification failed.');
  }

  const decoded = JSON.parse(base64UrlDecode(payload));
  if (!decoded.userId || !decoded.issuedAt || Date.now() - decoded.issuedAt > OAUTH_STATE_TTL_MS) {
    throw new Error('OAuth state expired.');
  }

  return decoded;
};

const buildGoogleConnectUrl = ({ userId, requestId }) => {
  ensureCalendarConfig();
  console.log('🚨 DEBUG REDIRECT URI:', process.env.GOOGLE_CALENDAR_REDIRECT_URI);

  const params = new URLSearchParams({
    client_id: getGoogleClientId(),
    redirect_uri: getGoogleRedirectUri(),
    response_type: 'code',
    access_type: 'offline',
    prompt: 'consent',
    include_granted_scopes: 'true',
    scope: GOOGLE_CALENDAR_SCOPE,
    state: buildOAuthState({ userId, requestId })
  });

  return `${GOOGLE_OAUTH_URL}?${params.toString()}`;
};

const googleTokenRequest = async (params, fallbackMessage) => {
  ensureCalendarConfig();

  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params)
  });

  if (!response.ok) {
    await throwGoogleError(response, fallbackMessage);
  }

  return (await parseResponsePayload(response)) || {};
};

const exchangeGoogleCode = async (code) =>
  googleTokenRequest(
    {
      code,
      client_id: getGoogleClientId(),
      client_secret: getGoogleClientSecret(),
      redirect_uri: getGoogleRedirectUri(),
      grant_type: 'authorization_code'
    },
    'Google OAuth exchange failed.'
  );

const refreshGoogleAccessToken = async (connection) => {
  if (!connection?.refresh_token) {
    throw new Error('Missing Google refresh token.');
  }

  const tokenPayload = await googleTokenRequest(
    {
      refresh_token: connection.refresh_token,
      client_id: getGoogleClientId(),
      client_secret: getGoogleClientSecret(),
      grant_type: 'refresh_token'
    },
    'Google token refresh failed.'
  );

  const tokenExpiresAt = tokenPayload.expires_in
    ? new Date(Date.now() + Number(tokenPayload.expires_in) * 1000).toISOString()
    : null;

  const { data, error } = await supabase
    .from('calendar_connections')
    .update({
      access_token: tokenPayload.access_token || connection.access_token,
      token_expires_at: tokenExpiresAt,
      sync_status: 'healthy',
      last_error: null
    })
    .eq('id', connection.id)
    .select('*')
    .single();

  if (error) throw error;
  return data;
};

const ensureFreshConnection = async (connection) => {
  if (!connection) {
    throw new Error('Calendar connection not found.');
  }

  const expiresAt = connection.token_expires_at ? Date.parse(connection.token_expires_at) : 0;
  if (connection.access_token && expiresAt - REFRESH_SKEW_MS > Date.now()) {
    return connection;
  }

  return refreshGoogleAccessToken(connection);
};

const googleCalendarRequest = async (path, { accessToken, method = 'GET', body, query } = {}) => {
  const url = new URL(`${GOOGLE_CALENDAR_API_BASE}${path}`);
  if (query) {
    Object.entries(query).forEach(([key, value]) => {
      if (value != null) {
        url.searchParams.set(key, String(value));
      }
    });
  }

  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${accessToken}`,
      ...(body ? { 'Content-Type': 'application/json' } : {})
    },
    ...(body ? { body: JSON.stringify(body) } : {})
  });

  if (!response.ok) {
    await throwGoogleError(response, `Google Calendar request failed: ${path}`);
  }

  return parseResponsePayload(response);
};

const normalizeCalendarRows = (connectionId, userId, items = []) =>
  items.map((item) => ({
    connection_id: connectionId,
    user_id: userId,
    external_calendar_id: item.id,
    summary: item.summary || item.id,
    primary_calendar: Boolean(item.primary),
    selected: item.selected !== false,
    access_role: item.accessRole || 'reader',
    background_color: item.backgroundColor || null,
    foreground_color: item.foregroundColor || null,
    time_zone: item.timeZone || null
  }));

export const compressBusyIntervals = (intervals = []) => {
  const sorted = intervals
    .filter((interval) => interval?.starts_at && interval?.ends_at)
    .map((interval) => ({
      starts_at: new Date(interval.starts_at).toISOString(),
      ends_at: new Date(interval.ends_at).toISOString()
    }))
    .sort((left, right) => Date.parse(left.starts_at) - Date.parse(right.starts_at));

  return sorted.reduce((merged, interval) => {
    const currentStart = Date.parse(interval.starts_at);
    const currentEnd = Date.parse(interval.ends_at);
    if (!Number.isFinite(currentStart) || !Number.isFinite(currentEnd) || currentStart >= currentEnd) {
      return merged;
    }

    const last = merged.at(-1);
    if (!last) {
      merged.push(interval);
      return merged;
    }

    if (currentStart <= Date.parse(last.ends_at)) {
      if (currentEnd > Date.parse(last.ends_at)) {
        last.ends_at = interval.ends_at;
      }
      return merged;
    }

    merged.push(interval);
    return merged;
  }, []);
};

const buildManagedEventDescription = (task) =>
  [
    'Managed by Student Task Orchestrator.',
    `Estimated minutes: ${task.estimated_minutes || 0}`,
    task.priority_band ? `Priority: ${task.priority_band}` : null,
    task.priority_reason ? `Reason: ${task.priority_reason}` : null
  ]
    .filter(Boolean)
    .join('\n');

export const buildManagedEventPayload = (task, timeZone) => ({
  summary: `Study: ${task.title}`,
  description: buildManagedEventDescription(task),
  start: {
    dateTime: `${task.scheduled_date}T${task.scheduled_start_time}`,
    timeZone
  },
  end: {
    dateTime: `${task.scheduled_date}T${task.scheduled_end_time}`,
    timeZone
  },
  source: {
    title: 'Student Task Orchestrator',
    url: getFrontendBaseUrl()
  },
  extendedProperties: {
    private: {
      managedBy: MANAGED_EVENT_SOURCE,
      subTaskId: String(task.id)
    }
  }
});

const buildManagedPayloadHash = (task, calendarId, timeZone) =>
  crypto
    .createHash('sha256')
    .update(
      JSON.stringify({
        id: task.id,
        title: task.title,
        scheduled_date: task.scheduled_date,
        scheduled_start_time: task.scheduled_start_time,
        scheduled_end_time: task.scheduled_end_time,
        estimated_minutes: task.estimated_minutes,
        priority_band: task.priority_band,
        priority_reason: task.priority_reason,
        calendarId,
        timeZone
      })
    )
    .digest('hex');

const queryWindow = () => {
  const start = new Date();
  const end = new Date(start.getTime() + SYNC_WINDOW_DAYS * 24 * 60 * 60 * 1000);
  return { start, end };
};

const normalizeBusyRows = (connectionId, userId, intervals) =>
  intervals.map((interval) => ({
    connection_id: connectionId,
    user_id: userId,
    external_calendar_id: MERGED_CALENDAR_ID,
    source: 'google',
    starts_at: interval.starts_at,
    ends_at: interval.ends_at
  }));

const upsertCalendarSnapshot = async ({ connectionId, userId, calendars, busyIntervals }) => {
  const { error: deleteCalendarError } = await supabase
    .from('calendar_calendars')
    .delete()
    .eq('connection_id', connectionId);

  if (deleteCalendarError) throw deleteCalendarError;

  if (calendars.length > 0) {
    const { error: insertCalendarError } = await supabase.from('calendar_calendars').insert(calendars);
    if (insertCalendarError) throw insertCalendarError;
  }

  const { error: deleteBusyError } = await supabase
    .from('calendar_busy_intervals')
    .delete()
    .eq('connection_id', connectionId);

  if (deleteBusyError) throw deleteBusyError;

  if (busyIntervals.length > 0) {
    const { error: insertBusyError } = await supabase.from('calendar_busy_intervals').insert(busyIntervals);
    if (insertBusyError) throw insertBusyError;
  }
};

const markConnectionStatus = async (connectionId, updates) => {
  const { error } = await supabase.from('calendar_connections').update(updates).eq('id', connectionId);
  if (error) throw error;
};

const getConnectionByUserId = async (userId) => {
  const { data, error } = await supabase
    .from('calendar_connections')
    .select('*')
    .eq('user_id', userId)
    .eq('provider', 'google')
    .maybeSingle();

  if (error) throw error;
  return data;
};

const pruneCalendarArtifacts = async () => {
  const { end } = queryWindow();
  const endIso = end.toISOString();

  const { error: pruneBusyError } = await supabase
    .from('calendar_busy_intervals')
    .delete()
    .lt('ends_at', new Date().toISOString());

  if (pruneBusyError) throw pruneBusyError;

  const { error: pruneFutureBusyError } = await supabase
    .from('calendar_busy_intervals')
    .delete()
    .gt('starts_at', endIso);

  if (pruneFutureBusyError) throw pruneFutureBusyError;

};

export const getCalendarConnectUrl = ({ userId, requestId }) => ({
  url: buildGoogleConnectUrl({ userId, requestId })
});

const syncBusyWindow = async ({ connection, requestId }) => {
  const hydratedConnection = await ensureFreshConnection(connection);
  const calendarListPayload = await googleCalendarRequest('/users/me/calendarList', {
    accessToken: hydratedConnection.access_token,
    query: { minAccessRole: 'reader' }
  });

  const calendars = normalizeCalendarRows(
    hydratedConnection.id,
    hydratedConnection.user_id,
    calendarListPayload?.items || []
  );

  const selectedCalendarIds = calendars.filter((calendar) => calendar.selected).map((calendar) => calendar.external_calendar_id);
  const { start, end } = queryWindow();
  const effectiveTimezone =
    calendars.find((calendar) => calendar.primary_calendar)?.time_zone ||
    calendars.find((calendar) => calendar.time_zone)?.time_zone ||
    getFallbackTimezone();

  let mergedBusy = [];
  if (selectedCalendarIds.length > 0) {
    const freeBusyPayload = await googleCalendarRequest('/freeBusy', {
      accessToken: hydratedConnection.access_token,
      method: 'POST',
      body: {
        timeMin: start.toISOString(),
        timeMax: end.toISOString(),
        timeZone: effectiveTimezone,
        items: selectedCalendarIds.map((id) => ({ id }))
      }
    });

    const rawIntervals = Object.values(freeBusyPayload?.calendars || {}).flatMap((calendar) =>
      (calendar?.busy || []).map((interval) => ({
        starts_at: interval.start,
        ends_at: interval.end
      }))
    );

    mergedBusy = compressBusyIntervals(rawIntervals);
  }

  await upsertCalendarSnapshot({
    connectionId: hydratedConnection.id,
    userId: hydratedConnection.user_id,
    calendars,
    busyIntervals: normalizeBusyRows(hydratedConnection.id, hydratedConnection.user_id, mergedBusy)
  });

  await markConnectionStatus(hydratedConnection.id, {
    email: decodeJwtPayload(hydratedConnection.id_token)?.email || hydratedConnection.email,
    sync_status: 'healthy',
    last_sync_at: new Date().toISOString(),
    next_sync_at: new Date(Date.now() + SYNC_INTERVAL_MS).toISOString(),
    last_error: null
  });

  log('info', 'Calendar busy sync complete', {
    requestId: getRequestId(requestId),
    userId: hydratedConnection.user_id,
    busyIntervalCount: mergedBusy.length,
    calendarCount: calendars.length
  });

  return {
    connection: hydratedConnection,
    calendars,
    mergedBusy,
    timeZone: effectiveTimezone
  };
};

const fetchManagedEventRows = async (userId) => {
  const { data, error } = await supabase
    .from('managed_schedule_events')
    .select('*')
    .eq('user_id', userId);

  if (error) throw error;
  return data || [];
};

const fetchScheduledTasks = async (userId) => {
  const { start, end } = queryWindow();
  const startDate = start.toISOString().slice(0, 10);
  const endDate = end.toISOString().slice(0, 10);

  const { data, error } = await supabase
    .from('sub_tasks')
    .select(
      'id, title, estimated_minutes, status, scheduled_date, scheduled_start_time, scheduled_end_time, priority_band, priority_reason'
    )
    .eq('user_id', userId)
    .neq('status', 'completed')
    .not('scheduled_date', 'is', null)
    .not('scheduled_start_time', 'is', null)
    .not('scheduled_end_time', 'is', null)
    .gte('scheduled_date', startDate)
    .lte('scheduled_date', endDate)
    .order('scheduled_date', { ascending: true })
    .order('scheduled_start_time', { ascending: true });

  if (error) throw error;
  return data || [];
};

const isWritableCalendar = (calendar) => ['owner', 'writer'].includes(calendar?.access_role);

const selectManagedCalendar = (calendars = []) =>
  calendars.find((calendar) => calendar.primary_calendar && calendar.selected && isWritableCalendar(calendar)) ||
  calendars.find((calendar) => calendar.selected && isWritableCalendar(calendar)) ||
  null;

const upsertManagedRows = async (rows) => {
  if (rows.length === 0) return;

  const { error } = await supabase
    .from('managed_schedule_events')
    .upsert(rows, { onConflict: 'user_id,sub_task_id' });

  if (error) throw error;
};

const deleteManagedRows = async (userId, subTaskIds) => {
  if (subTaskIds.length === 0) return;
  const { error } = await supabase
    .from('managed_schedule_events')
    .delete()
    .eq('user_id', userId)
    .in('sub_task_id', subTaskIds);

  if (error) throw error;
};

const deleteGoogleEventIfPresent = async (accessToken, calendarId, externalEventId) => {
  if (!externalEventId || !calendarId) return;
  try {
    await googleCalendarRequest(`/calendars/${encodeURIComponent(calendarId)}/events/${encodeURIComponent(externalEventId)}`, {
      accessToken,
      method: 'DELETE'
    });
  } catch (error) {
    if (error.status !== 404) {
      throw error;
    }
  }
};

const rebuildManagedEventsInternal = async ({ connection, calendars, timeZone, requestId }) => {
  const hydratedConnection = await ensureFreshConnection(connection);
  const targetCalendar = selectManagedCalendar(calendars);
  if (!targetCalendar) {
    throw new Error('No writable Google calendar available.');
  }

  const scheduledTasks = await fetchScheduledTasks(hydratedConnection.user_id);
  const existingRows = await fetchManagedEventRows(hydratedConnection.user_id);
  const existingBySubTaskId = new Map(existingRows.map((row) => [row.sub_task_id, row]));

  const nextRows = [];
  const activeSubTaskIds = new Set();

  for (const task of scheduledTasks) {
    const payload = buildManagedEventPayload(task, targetCalendar.time_zone || timeZone);
    const payloadHash = buildManagedPayloadHash(
      task,
      targetCalendar.external_calendar_id,
      targetCalendar.time_zone || timeZone
    );
    const existingRow = existingBySubTaskId.get(task.id);

    let externalEventId = existingRow?.external_event_id || null;
    let eventStart = existingRow?.starts_at || null;
    let eventEnd = existingRow?.ends_at || null;
    if (!existingRow || existingRow.payload_hash !== payloadHash || existingRow.external_calendar_id !== targetCalendar.external_calendar_id) {
      const eventPayload =
        existingRow?.external_event_id && existingRow.external_calendar_id === targetCalendar.external_calendar_id
          ? await googleCalendarRequest(
              `/calendars/${encodeURIComponent(existingRow.external_calendar_id)}/events/${encodeURIComponent(existingRow.external_event_id)}`,
              {
                accessToken: hydratedConnection.access_token,
                method: 'PUT',
                body: payload
              }
            )
          : await (async () => {
              if (existingRow?.external_event_id) {
                await deleteGoogleEventIfPresent(
                  hydratedConnection.access_token,
                  existingRow.external_calendar_id,
                  existingRow.external_event_id
                );
              }
              return googleCalendarRequest(`/calendars/${encodeURIComponent(targetCalendar.external_calendar_id)}/events`, {
                accessToken: hydratedConnection.access_token,
                method: 'POST',
                body: payload
              });
            })();

      externalEventId = eventPayload?.id || externalEventId;
      eventStart = eventPayload?.start?.dateTime || eventPayload?.start?.date || eventStart;
      eventEnd = eventPayload?.end?.dateTime || eventPayload?.end?.date || eventEnd;
    }

    nextRows.push({
      user_id: hydratedConnection.user_id,
      connection_id: hydratedConnection.id,
      sub_task_id: task.id,
      external_calendar_id: targetCalendar.external_calendar_id,
      external_event_id: externalEventId,
      starts_at: eventStart || payload.start.dateTime,
      ends_at: eventEnd || payload.end.dateTime,
      status: 'synced',
      last_synced_at: new Date().toISOString(),
      last_error: null,
      payload: payload,
      payload_hash: payloadHash
    });
    activeSubTaskIds.add(task.id);
  }

  const staleRows = existingRows.filter((row) => !activeSubTaskIds.has(row.sub_task_id));
  for (const row of staleRows) {
    await deleteGoogleEventIfPresent(hydratedConnection.access_token, row.external_calendar_id, row.external_event_id);
  }

  await upsertManagedRows(nextRows);
  await deleteManagedRows(
    hydratedConnection.user_id,
    staleRows.map((row) => row.sub_task_id)
  );

  log('info', 'Managed calendar rebuild complete', {
    requestId: getRequestId(requestId),
    userId: hydratedConnection.user_id,
    taskCount: nextRows.length,
    removedCount: staleRows.length
  });

  return {
    targetCalendarId: targetCalendar.external_calendar_id,
    syncedCount: nextRows.length,
    removedCount: staleRows.length
  };
};

export const syncCalendarForUser = async ({ userId, rebuildManaged = false, requestId } = {}) => {
  const requestIdValue = getRequestId(requestId);
  const connection = await getConnectionByUserId(userId);
  if (!connection) {
    throw new Error('Connect Google Calendar first.');
  }

  try {
    const syncState = await syncBusyWindow({ connection, requestId: requestIdValue });
    const managed = rebuildManaged
      ? await rebuildManagedEventsInternal({
          connection: syncState.connection,
          calendars: syncState.calendars,
          timeZone: syncState.timeZone,
          requestId: requestIdValue
        })
      : null;

    return {
      ...(await getCalendarStatus({ userId })),
      managed
    };
  } catch (error) {
    await markConnectionStatus(connection.id, {
      sync_status: 'error',
      next_sync_at: new Date(Date.now() + SYNC_INTERVAL_MS).toISOString(),
      last_error: error.message
    });
    throw error;
  }
};

export const rebuildManagedCalendarForUser = async ({ userId, requestId } = {}) =>
  syncCalendarForUser({ userId, rebuildManaged: true, requestId });

export const getCalendarStatus = async ({ userId }) => {
  const connection = await getConnectionByUserId(userId);
  if (!connection) {
    return {
      configured: hasCalendarConfig(),
      connected: false,
      provider: 'google',
      syncHealth: 'disconnected',
      managedPolicyNotice: 'Managed study blocks mirror your weekly schedule into your Google Calendar primary calendar.'
    };
  }

  const [
    { count: calendarCount, error: calendarCountError },
    { count: busyIntervalCount, error: busyCountError },
    { count: managedEventCount, error: managedCountError },
    { data: calendars, error: calendarsError }
  ] =
    await Promise.all([
      supabase.from('calendar_calendars').select('*', { count: 'exact', head: true }).eq('connection_id', connection.id),
      supabase.from('calendar_busy_intervals').select('*', { count: 'exact', head: true }).eq('connection_id', connection.id),
      supabase.from('managed_schedule_events').select('*', { count: 'exact', head: true }).eq('connection_id', connection.id),
      supabase
        .from('calendar_calendars')
        .select(
          'external_calendar_id, summary, primary_calendar, selected, access_role, background_color, foreground_color, time_zone'
        )
        .eq('connection_id', connection.id)
        .order('primary_calendar', { ascending: false })
        .order('summary', { ascending: true })
    ]);

  if (calendarCountError || busyCountError || managedCountError || calendarsError) {
    throw calendarCountError || busyCountError || managedCountError || calendarsError;
  }

  return {
    configured: hasCalendarConfig(),
    connected: true,
    provider: 'google',
    email: connection.email,
    syncHealth: connection.sync_status,
    lastSyncAt: connection.last_sync_at,
    nextSyncAt: connection.next_sync_at,
    lastError: connection.last_error,
    calendarCount: calendarCount || 0,
    busyIntervalCount: busyIntervalCount || 0,
    managedEventCount: managedEventCount || 0,
    calendars: calendars || [],
    managedPolicyNotice:
      'Managed study blocks mirror your weekly schedule into your Google Calendar primary calendar. Rebuild after schedule edits.'
  };
};

export const disconnectCalendarForUser = async ({ userId, requestId } = {}) => {
  const connection = await getConnectionByUserId(userId);
  if (!connection) {
    return { disconnected: true };
  }

  const managedRows = await fetchManagedEventRows(userId);
  try {
    const hydratedConnection = await ensureFreshConnection(connection);
    for (const row of managedRows) {
      await deleteGoogleEventIfPresent(
        hydratedConnection.access_token,
        row.external_calendar_id,
        row.external_event_id
      );
    }
  } catch (error) {
    log('warn', 'Calendar disconnect skipped remote cleanup', {
      requestId: getRequestId(requestId),
      userId,
      error
    });
  }

  const { error } = await supabase
    .from('calendar_connections')
    .delete()
    .eq('user_id', userId)
    .eq('provider', 'google');

  if (error) throw error;

  return { disconnected: true };
};

export const completeCalendarOAuth = async ({ code, state, requestId } = {}) => {
  ensureCalendarConfig();
  const parsedState = parseOAuthState(state);
  const tokenPayload = await exchangeGoogleCode(code);
  const existingConnection = await getConnectionByUserId(parsedState.userId);
  const idTokenClaims = decodeJwtPayload(tokenPayload.id_token);
  const refreshToken = tokenPayload.refresh_token || existingConnection?.refresh_token || null;

  if (!refreshToken) {
    throw new Error('Google did not return a refresh token. Remove the existing connection and try again.');
  }

  const tokenExpiresAt = tokenPayload.expires_in
    ? new Date(Date.now() + Number(tokenPayload.expires_in) * 1000).toISOString()
    : null;

  const upsertPayload = {
    user_id: parsedState.userId,
    provider: 'google',
    email: idTokenClaims.email || existingConnection?.email || null,
    access_token: tokenPayload.access_token || existingConnection?.access_token || null,
    refresh_token: refreshToken,
    id_token: tokenPayload.id_token || existingConnection?.id_token || null,
    token_expires_at: tokenExpiresAt,
    granted_scopes: String(tokenPayload.scope || '').split(/\s+/).filter(Boolean),
    sync_status: 'pending',
    next_sync_at: new Date().toISOString(),
    last_error: null
  };

  const { data, error } = await supabase
    .from('calendar_connections')
    .upsert([upsertPayload], { onConflict: 'user_id,provider' })
    .select('*')
    .single();

  if (error) throw error;

  log('info', 'Calendar OAuth completed', {
    requestId: getRequestId(requestId),
    userId: parsedState.userId
  });

  await syncCalendarForUser({ userId: parsedState.userId, rebuildManaged: true, requestId });
  return data;
};

const syncDueConnections = async () => {
  const { data, error } = await supabase
    .from('calendar_connections')
    .select('user_id, next_sync_at')
    .eq('provider', 'google')
    .in('sync_status', ['pending', 'healthy', 'error']);

  if (error) throw error;

  const now = Date.now();
  const dueRows = (data || []).filter((row) => !row.next_sync_at || Date.parse(row.next_sync_at) <= now);

  for (const row of dueRows) {
    try {
      await syncCalendarForUser({ userId: row.user_id, rebuildManaged: true });
    } catch (syncError) {
      log('warn', 'Scheduled calendar sync failed', {
        userId: row.user_id,
        error: syncError
      });
    }
  }
};

export const startCalendarSyncLoop = () => {
  if (calendarLoopHandle || !hasCalendarConfig()) {
    return;
  }

  const executeTick = async () => {
    try {
      const pruneStamp = new Date().toISOString().slice(0, 10);
      if (pruneStamp !== lastPruneStamp) {
        await pruneCalendarArtifacts();
        lastPruneStamp = pruneStamp;
      }
      await syncDueConnections();
    } catch (error) {
      log('warn', 'Calendar sync loop tick failed', { error });
    }
  };

  void executeTick();
  calendarLoopHandle = setInterval(executeTick, LOOP_TICK_MS);

  if (typeof calendarLoopHandle.unref === 'function') {
    calendarLoopHandle.unref();
  }
};

export const getCalendarCallbackRedirect = buildCallbackRedirect;
