import express from 'express';
import { completeFocusSession } from '../controllers/focusController.js';

const router = express.Router();

router.post('/complete', completeFocusSession);

export default router;
