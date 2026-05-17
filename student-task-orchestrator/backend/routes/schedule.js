import express from 'express';
import { persistWeeklySchedule } from '../controllers/scheduleController.js';

const router = express.Router();

router.post('/persist', persistWeeklySchedule);

export default router;
