import { supabase } from '../config/supabase.js';
import { createTasksFromAcademicText } from './aiController.js';
import {
  completeDriveOAuth,
  disconnectDriveForUser,
  getDriveConnectUrl,
  getDriveStatus,
  listDriveFilesForUser,
  readDriveFileTextForUser,
} from '../lib/driveService.js';

const getErrorStatusCode = (error) => {
  if (Number.isInteger(error?.statusCode)) return error.statusCode;
  if (Number.isInteger(error?.status)) return error.status;
  if (error?.message === 'Connect Google Drive first.') return 400;
  return 500;
};

export const getDriveIntegrationStatus = async (req, res) => {
  try {
    const status = await getDriveStatus({ userId: req.user.id });
    res.status(200).json({ ...status, connected: status.connected === true });
  } catch (error) {
    res.status(500).json({ error: 'Failed to load Google Drive status', details: error.message });
  }
};

export const getDriveIntegrationConnectUrl = async (req, res) => {
  try {
    const payload = getDriveConnectUrl({ userId: req.user.id, requestId: req.requestId });
    res.status(200).json(payload);
  } catch (error) {
    res.status(503).json({ error: 'Google Drive integration unavailable', details: error.message });
  }
};

export const listDriveFiles = async (req, res) => {
  try {
    const payload = await listDriveFilesForUser({
      userId: req.user.id,
      query: req.query?.q,
      pageToken: req.query?.pageToken,
      pageSize: req.query?.pageSize,
    });
    res.status(200).json(payload);
  } catch (error) {
    const statusCode = getErrorStatusCode(error);
    res.status(statusCode).json({ error: 'Failed to list Google Drive files', details: error.message });
  }
};

export const importDriveFile = async (req, res) => {
  try {
    const { metadata, text } = await readDriveFileTextForUser({
      userId: req.user.id,
      fileId: req.body?.fileId || req.body?.file_id,
    });
    const payload = await createTasksFromAcademicText({
      text,
      sourceName: metadata.name || 'Google Drive file',
      db: req.supabase || supabase,
      userId: req.user.id,
    });

    res.status(200).json({
      message: payload.message,
      file: metadata,
      actionsParsed: payload.actionsParsed,
      created: payload.created,
      tasks: payload.tasks,
    });
  } catch (error) {
    const statusCode = getErrorStatusCode(error);
    res.status(statusCode).json({ error: 'Failed to import Google Drive file', details: error.message });
  }
};

export const disconnectDriveIntegration = async (req, res) => {
  try {
    const payload = await disconnectDriveForUser({ userId: req.user.id });
    res.status(200).json(payload);
  } catch (error) {
    res.status(500).json({ error: 'Failed to disconnect Google Drive', details: error.message });
  }
};

export const completeDriveOAuthCallback = async (req, res) => {
  const { code, state, error } = req.query || {};
  if (error || !code || !state) {
    return res.redirect('rakanstudent://drive-error');
  }

  try {
    await completeDriveOAuth({ code: String(code), state: String(state), requestId: req.requestId });
    return res.redirect('rakanstudent://drive-success');
  } catch (callbackError) {
    console.error('Google Drive OAuth Callback Failed:', callbackError.message, {
      requestId: req.requestId,
      hasCode: Boolean(code),
      hasState: Boolean(state),
    });
    return res.redirect('rakanstudent://drive-error');
  }
};
