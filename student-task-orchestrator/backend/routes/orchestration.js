import express from 'express';
import {
  cancelRun,
  createRun,
  getOverview,
  getRun,
  retryRun
} from '../controllers/orchestrationController.js';

const router = express.Router();

router.get('/overview', getOverview);
router.post('/runs', createRun);
router.get('/runs/:id', getRun);
router.post('/runs/:id/retry', retryRun);
router.post('/runs/:id/cancel', cancelRun);

export default router;
