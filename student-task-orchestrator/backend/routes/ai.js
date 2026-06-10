import express from 'express';

import {
  chatWithAi,
  orchestrateGoal,
  visionFlashcards,
  visionParse,
} from '../controllers/aiController.js';

const router = express.Router();

router.post('/orchestrate', orchestrateGoal);
router.post('/chat', chatWithAi);
router.post('/vision-parse', visionParse);
router.post('/vision-flashcards', visionFlashcards);

export default router;
