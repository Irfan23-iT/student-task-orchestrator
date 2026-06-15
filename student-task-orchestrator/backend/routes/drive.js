import express from 'express';

import {
  disconnectDriveIntegration,
  getDriveIntegrationConnectUrl,
  getDriveIntegrationStatus,
  importDriveFile,
  listDriveFiles,
} from '../controllers/driveController.js';

const router = express.Router();

router.get('/status', getDriveIntegrationStatus);
router.post('/connect-url', getDriveIntegrationConnectUrl);
router.get('/files', listDriveFiles);
router.post('/import', importDriveFile);
router.delete('/connection', disconnectDriveIntegration);

export default router;
