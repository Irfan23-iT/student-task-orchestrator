import express from 'express';

import { chatWithAi, orchestrateGoal } from '../controllers/aiController.js';

const router = express.Router();

router.post('/orchestrate', orchestrateGoal);
router.post('/chat', chatWithAi);

export default router;
