import express from 'express';
import {
  getProfileSettings,
  getSystemReadiness,
  upsertProfileSettings
} from '../controllers/settingsController.js';

const router = express.Router();

router.get('/profile', getProfileSettings);
router.get('/readiness', getSystemReadiness);
router.put('/profile', upsertProfileSettings);

export default router;
