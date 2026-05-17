import express from 'express';
import {
  addWorkspaceMember,
  assignWorkspaceTask,
  createWorkspace,
  getWorkspaceOverview,
  getWorkspaceShare,
  joinWorkspace,
  updateWorkspaceMember
} from '../controllers/workspaceController.js';

const router = express.Router();

router.get('/overview', getWorkspaceOverview);
router.post('/join', joinWorkspace);
router.post('/', createWorkspace);
router.get('/:id/share', getWorkspaceShare);
router.post('/:id/members', addWorkspaceMember);
router.patch('/:id/members/:memberUserId', updateWorkspaceMember);
router.post('/:id/tasks', assignWorkspaceTask);

export default router;
