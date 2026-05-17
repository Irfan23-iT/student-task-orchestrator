import express from 'express';
import multer from 'multer';
import {
  createTask,
  deleteAllTasks,
  deleteSessionTasks,
  deleteTask,
  getPrimaryTasks,
  getTaskRows,
  getTasks,
  getTasksByRun,
  saveTasksForRun,
  updateSubTask
} from '../controllers/taskController.js';
import { importTasksFromCsv } from '../controllers/importController.js';

const router = express.Router();

const memoryUpload = multer({ storage: multer.memoryStorage() });

router.get('/', getTasks);
router.post('/', createTask);
router.get('/primary', getPrimaryTasks);
router.get('/rows', getTaskRows);
router.get('/runs/:runId', getTasksByRun);
router.patch('/subtasks/:id', updateSubTask);
router.delete('/', deleteAllTasks);
router.delete('/session', deleteSessionTasks);
router.delete('/:id', deleteTask);
router.post('/save-run', saveTasksForRun);
router.post('/import', memoryUpload.single('file'), importTasksFromCsv);

export default router;
