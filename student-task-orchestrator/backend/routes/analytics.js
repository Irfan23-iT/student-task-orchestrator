import express from 'express';
import {
  createReminder,
  deletePushSubscription,
  getAnalyticsOverview,
  listReminders,
  updateReminder,
  upsertPushSubscription,
  upsertNotificationPreferences
} from '../controllers/analyticsController.js';

const router = express.Router();

router.get('/overview', getAnalyticsOverview);
router.put('/preferences', upsertNotificationPreferences);
router.get('/reminders', listReminders);
router.post('/reminders', createReminder);
router.patch('/reminders/:id', updateReminder);
router.put('/push-subscriptions', upsertPushSubscription);
router.delete('/push-subscriptions', deletePushSubscription);

export default router;
