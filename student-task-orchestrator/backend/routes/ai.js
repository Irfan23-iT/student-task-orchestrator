import express from 'express';

import {
  chatWithAi,
  orchestrateGoal,
  visionParse,
} from '../controllers/aiController.js';

const router = express.Router();

router.post('/orchestrate', orchestrateGoal);
router.post('/chat', chatWithAi);
router.post('/vision-parse', visionParse);

export default router;
