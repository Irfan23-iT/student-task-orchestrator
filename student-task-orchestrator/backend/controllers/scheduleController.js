import { supabase } from '../config/supabase.js';

export const persistWeeklySchedule = async (req, res) => {
  try {
    const logicalTaskIds = Array.isArray(req.body?.logicalTaskIds) ? req.body.logicalTaskIds : [];
    const scheduleRows = Array.isArray(req.body?.scheduleRows) ? req.body.scheduleRows : [];

    if (logicalTaskIds.length === 0 || scheduleRows.length === 0) {
      return res.status(400).json({
        error: 'logicalTaskIds and scheduleRows are required.'
      });
    }

    const { data, error } = await supabase.rpc('persist_weekly_schedule', {
      p_schedule_rows: scheduleRows,
      p_logical_task_ids: logicalTaskIds
    });

    if (error) throw error;

    res.status(200).json({ result: data });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to persist schedule',
      details: error.message
    });
  }
};
