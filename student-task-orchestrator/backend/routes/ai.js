import express from 'express';
import multer from 'multer';

import {
  chatWithAi,
  orchestrateGoal,
  pdfToTasks,
  visionFlashcards,
  visionParse,
  voiceToTask,
} from '../controllers/aiController.js';

const router = express.Router();
const pdfUpload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 15 * 1024 * 1024 } });

router.post('/orchestrate', orchestrateGoal);
router.post('/chat', chatWithAi);
router.post('/voice-task', voiceToTask);
router.post('/pdf-tasks', pdfUpload.single('file'), pdfToTasks);
router.post('/vision-parse', visionParse);
router.post('/vision-flashcards', visionFlashcards);

export default router;
