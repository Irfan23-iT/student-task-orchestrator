import express from 'express';
import {
  bulkCreateFixedClasses,
  deleteFixedClass,
  disconnectCalendarIntegration,
  getCalendarIntegrationConnectUrl,
  getCalendarIntegrationStatus,
  listFixedClasses,
  rebuildManagedCalendar,
  syncCalendarIntegration,
  updateFixedClass
} from '../controllers/calendarController.js';

const router = express.Router();

router.get('/status', getCalendarIntegrationStatus);
router.post('/connect-url', getCalendarIntegrationConnectUrl);
router.post('/sync', syncCalendarIntegration);
router.post('/rebuild', rebuildManagedCalendar);
router.delete('/connection', disconnectCalendarIntegration);
router.get('/fixed-classes', listFixedClasses);
router.post('/fixed-classes/bulk', bulkCreateFixedClasses);
router.put('/fixed-classes/:id', updateFixedClass);
router.delete('/fixed-classes/:id', deleteFixedClass);

export default router;
