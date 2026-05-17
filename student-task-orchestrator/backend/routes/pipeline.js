import express from 'express';
import { getLatestPipelineState, upsertPipelineState } from '../controllers/pipelineController.js';

const router = express.Router();

router.get('/state/latest', getLatestPipelineState);
router.post('/state', upsertPipelineState);

export default router;
