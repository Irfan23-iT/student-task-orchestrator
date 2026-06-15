import crypto from 'node:crypto';
import { createRequire } from 'node:module';

import { serviceSupabase } from '../config/supabase.js';
import { log } from './logger.js';

const require = createRequire(import.meta.url);
const { PDFParse } = require('pdf-parse');

const GOOGLE_OAUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth';
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const GOOGLE_DRIVE_API_BASE = 'https://www.googleapis.com/drive/v3';
const GOOGLE_DRIVE_SCOPE = 'https://www.googleapis.com/auth/drive.readonly';
const OAUTH_STATE_TTL_MS = 30 * 60 * 1000;
const REFRESH_SKEW_MS = 5 * 60 * 1000;
const MAX_TEXT_BYTES = 300_000;

const base64UrlEncode = (value) => Buffer.from(value, 'utf8').toString('base64url');
const base64UrlDecode = (value) => Buffer.from(value, 'base64url').toString('utf8');

const getRequestId = (requestId) => requestId || crypto.randomUUID();
const getGoogleClientId = () => process.env.GOOGLE_DRIVE_CLIENT_ID || process.env.GOOGLE_CLIENT_ID || '';
const getGoogleClientSecret = () => process.env.GOOGLE_DRIVE_CLIENT_SECRET || process.env.GOOGLE_CLIENT_SECRET || '';
const getGoogleRedirectUri = () => process.env.GOOGLE_DRIVE_REDIRECT_URI || '';
const hasDriveConfig = () => Boolean(getGoogleClientId() && getGoogleClientSecret() && getGoogleRedirectUri());

export const getDriveIntegrationCapabilities = () => ({
  configured: hasDriveConfig(),
});

const ensureDriveConfig = () => {
  if (!hasDriveConfig()) {
    throw new Error('Google Drive OAuth is not configured.');
  }
};

const getStateSecret = () =>
  process.env.GOOGLE_DRIVE_STATE_SECRET ||
  process.env.GOOGLE_OAUTH_STATE_SECRET ||
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  'drive-state-secret';

const parseResponsePayload = async (response) => {
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.toLowerCase().includes('application/json')) return null;

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

const buildOAuthState = ({ userId, requestId }) => {
  const payload = base64UrlEncode(
    JSON.stringify({
      userId,
      requestId: getRequestId(requestId),
      issuedAt: Date.now(),
      nonce: crypto.randomUUID(),
    }),
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

const googleTokenRequest = async (params, fallbackMessage) => {
  ensureDriveConfig();
  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(params),
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
      grant_type: 'authorization_code',
    },
    'Google Drive OAuth exchange failed.',
  );

const refreshGoogleAccessToken = async (connection) => {
  if (!connection?.refresh_token) {
    throw new Error('Missing Google Drive refresh token.');
  }

  const tokenPayload = await googleTokenRequest(
    {
      refresh_token: connection.refresh_token,
      client_id: getGoogleClientId(),
      client_secret: getGoogleClientSecret(),
      grant_type: 'refresh_token',
    },
    'Google Drive token refresh failed.',
  );

  const tokenExpiresAt = tokenPayload.expires_in
    ? new Date(Date.now() + Number(tokenPayload.expires_in) * 1000).toISOString()
    : null;

  const { data, error } = await serviceSupabase
    .from('drive_connections')
    .update({
      access_token: tokenPayload.access_token || connection.access_token,
      token_expires_at: tokenExpiresAt,
      status: 'healthy',
      last_error: null,
    })
    .eq('id', connection.id)
    .select('*')
    .single();

  if (error) throw error;
  return data;
};

const ensureFreshConnection = async (connection) => {
  if (!connection) {
    throw new Error('Connect Google Drive first.');
  }

  const expiresAt = connection.token_expires_at ? Date.parse(connection.token_expires_at) : 0;
  if (connection.access_token && expiresAt - REFRESH_SKEW_MS > Date.now()) {
    return connection;
  }

  return refreshGoogleAccessToken(connection);
};

const getConnectionByUserId = async (userId) => {
  const { data, error } = await serviceSupabase
    .from('drive_connections')
    .select('*')
    .eq('user_id', userId)
    .eq('provider', 'google')
    .maybeSingle();

  if (error) throw error;
  return data;
};

const googleDriveRequest = async (path, { accessToken, method = 'GET', query, exportMimeType } = {}) => {
  const url = new URL(`${GOOGLE_DRIVE_API_BASE}${path}`);
  if (query) {
    Object.entries(query).forEach(([key, value]) => {
      if (value != null) url.searchParams.set(key, String(value));
    });
  }
  if (exportMimeType) {
    url.searchParams.set('mimeType', exportMimeType);
  }

  const response = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${accessToken}` },
  });

  if (!response.ok) {
    await throwGoogleError(response, `Google Drive request failed: ${path}`);
  }

  return response;
};

const readResponseText = async (response) => {
  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.byteLength > MAX_TEXT_BYTES) {
    throw new Error('Google Drive file is too large to import as text.');
  }
  return buffer.toString('utf8');
};

const readPdfText = async (response) => {
  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.byteLength > MAX_TEXT_BYTES * 5) {
    throw new Error('Google Drive PDF is too large to import.');
  }

  let parser;
  try {
    parser = new PDFParse({ data: buffer });
    const parsed = await parser.getText();
    return parsed.text || '';
  } finally {
    if (parser) await parser.destroy();
  }
};

export const getDriveConnectUrl = ({ userId, requestId }) => {
  ensureDriveConfig();
  const params = new URLSearchParams({
    client_id: getGoogleClientId(),
    redirect_uri: getGoogleRedirectUri(),
    response_type: 'code',
    access_type: 'offline',
    prompt: 'consent',
    include_granted_scopes: 'true',
    scope: GOOGLE_DRIVE_SCOPE,
    state: buildOAuthState({ userId, requestId }),
  });

  return { url: `${GOOGLE_OAUTH_URL}?${params.toString()}` };
};

export const completeDriveOAuth = async ({ code, state, requestId } = {}) => {
  ensureDriveConfig();
  const parsedState = parseOAuthState(state);
  const tokenPayload = await exchangeGoogleCode(code);
  const existingConnection = await getConnectionByUserId(parsedState.userId);
  const idTokenClaims = decodeJwtPayload(tokenPayload.id_token);
  const refreshToken = tokenPayload.refresh_token || existingConnection?.refresh_token || null;

  if (!refreshToken) {
    throw new Error('Google did not return a Drive refresh token. Remove the existing connection and try again.');
  }

  const tokenExpiresAt = tokenPayload.expires_in
    ? new Date(Date.now() + Number(tokenPayload.expires_in) * 1000).toISOString()
    : null;

  const { data, error } = await serviceSupabase
    .from('drive_connections')
    .upsert(
      [
        {
          user_id: parsedState.userId,
          provider: 'google',
          email: idTokenClaims.email || existingConnection?.email || null,
          access_token: tokenPayload.access_token || existingConnection?.access_token || null,
          refresh_token: refreshToken,
          id_token: tokenPayload.id_token || existingConnection?.id_token || null,
          token_expires_at: tokenExpiresAt,
          granted_scopes: String(tokenPayload.scope || '').split(/\s+/).filter(Boolean),
          status: 'healthy',
          last_error: null,
        },
      ],
      { onConflict: 'user_id,provider' },
    )
    .select('*')
    .single();

  if (error) throw error;
  log('info', 'Google Drive OAuth completed', { requestId: getRequestId(requestId), userId: parsedState.userId });
  return data;
};

export const getDriveStatus = async ({ userId } = {}) => {
  const connection = await getConnectionByUserId(userId);
  if (!connection) {
    return { configured: hasDriveConfig(), connected: false, provider: 'google' };
  }

  return {
    configured: hasDriveConfig(),
    connected: true,
    provider: 'google',
    email: connection.email,
    status: connection.status,
    lastError: connection.last_error,
    updatedAt: connection.updated_at,
  };
};

export const disconnectDriveForUser = async ({ userId } = {}) => {
  const { error } = await serviceSupabase
    .from('drive_connections')
    .delete()
    .eq('user_id', userId)
    .eq('provider', 'google');

  if (error) throw error;
  return { disconnected: true };
};

export const listDriveFilesForUser = async ({ userId, query = '', pageToken = '', pageSize = 20 } = {}) => {
  const connection = await ensureFreshConnection(await getConnectionByUserId(userId));
  const searchParts = [
    'trashed = false',
    "(mimeType = 'application/pdf' or mimeType = 'text/plain' or mimeType = 'application/vnd.google-apps.document')",
  ];
  const trimmedQuery = String(query || '').trim().replace(/'/g, "\\'");
  if (trimmedQuery) {
    searchParts.push(`name contains '${trimmedQuery}'`);
  }

  const response = await googleDriveRequest('/files', {
    accessToken: connection.access_token,
    query: {
      q: searchParts.join(' and '),
      pageSize: Math.min(Math.max(Number(pageSize) || 20, 1), 50),
      pageToken: String(pageToken || '') || undefined,
      fields: 'nextPageToken, files(id, name, mimeType, size, modifiedTime, webViewLink, iconLink)',
      orderBy: 'modifiedTime desc',
    },
  });

  const payload = (await parseResponsePayload(response)) || {};
  return {
    files: payload.files || [],
    nextPageToken: payload.nextPageToken || null,
  };
};

export const readDriveFileTextForUser = async ({ userId, fileId } = {}) => {
  const normalizedFileId = String(fileId || '').trim();
  if (!normalizedFileId) {
    const error = new Error('fileId is required.');
    error.statusCode = 400;
    throw error;
  }

  const connection = await ensureFreshConnection(await getConnectionByUserId(userId));
  const metadataResponse = await googleDriveRequest(`/files/${encodeURIComponent(normalizedFileId)}`, {
    accessToken: connection.access_token,
    query: { fields: 'id, name, mimeType, size, modifiedTime, webViewLink' },
  });
  const metadata = (await parseResponsePayload(metadataResponse)) || {};
  const mimeType = String(metadata.mimeType || '');

  let text = '';
  if (mimeType === 'application/vnd.google-apps.document') {
    const exportResponse = await googleDriveRequest(`/files/${encodeURIComponent(normalizedFileId)}/export`, {
      accessToken: connection.access_token,
      exportMimeType: 'text/plain',
    });
    text = await readResponseText(exportResponse);
  } else if (mimeType === 'application/pdf') {
    const fileResponse = await googleDriveRequest(`/files/${encodeURIComponent(normalizedFileId)}`, {
      accessToken: connection.access_token,
      query: { alt: 'media' },
    });
    text = await readPdfText(fileResponse);
  } else if (mimeType.startsWith('text/')) {
    const fileResponse = await googleDriveRequest(`/files/${encodeURIComponent(normalizedFileId)}`, {
      accessToken: connection.access_token,
      query: { alt: 'media' },
    });
    text = await readResponseText(fileResponse);
  } else {
    const error = new Error('Google Drive file type is not supported for import.');
    error.statusCode = 415;
    throw error;
  }

  const trimmedText = String(text || '').trim();
  if (!trimmedText) {
    const error = new Error('Google Drive file did not contain readable text.');
    error.statusCode = 422;
    throw error;
  }

  return { metadata, text: trimmedText.slice(0, MAX_TEXT_BYTES) };
};
