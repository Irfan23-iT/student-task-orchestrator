import { supabase } from '../config/supabase.js';
import { log } from '../lib/logger.js';
import { createUniqueInviteCode, normalizeInviteCode } from '../lib/workspaceInvites.js';

const WORKSPACE_ROLES = new Set(['owner', 'manager', 'member', 'viewer']);
const WORKSPACE_STATUSES = new Set(['active', 'completed', 'blocked', 'archived']);
const MEMBER_STATUSES = new Set(['active', 'invited', 'removed']);

const assert = (condition, message, statusCode = 400) => {
  if (condition) return;
  const error = new Error(message);
  error.statusCode = statusCode;
  throw error;
};

const ensureWorkspaceManager = async (workspaceId, userId) => {
  const { data: workspace, error: workspaceError } = await supabase
    .from('workspaces')
    .select('id, owner_user_id')
    .eq('id', workspaceId)
    .maybeSingle();

  if (workspaceError) throw workspaceError;
  if (!workspace) {
    const error = new Error('Workspace not found.');
    error.statusCode = 404;
    throw error;
  }

  if (workspace.owner_user_id === userId) {
    return workspace;
  }

  const { data: membership, error: membershipError } = await supabase
    .from('workspace_members')
    .select('role, status')
    .eq('workspace_id', workspaceId)
    .eq('user_id', userId)
    .maybeSingle();

  if (membershipError) throw membershipError;

  if (!membership || membership.status !== 'active' || !['owner', 'manager'].includes(membership.role)) {
    const error = new Error('Workspace manager access required.');
    error.statusCode = 403;
    throw error;
  }

  return workspace;
};

const readWorkspaceMember = async (workspaceId, memberUserId) => {
  const { data, error } = await supabase
    .from('workspace_members')
    .select('*')
    .eq('workspace_id', workspaceId)
    .eq('user_id', memberUserId)
    .maybeSingle();

  if (error) throw error;
  return data || null;
};

const inviteCodeExists = async (inviteCode) => {
  const { data, error } = await supabase
    .from('workspaces')
    .select('id')
    .eq('invite_code', inviteCode)
    .maybeSingle();

  if (error) throw error;
  return Boolean(data?.id);
};

const ensureWorkspaceInviteCode = async (workspace) => {
  if (workspace?.invite_code) {
    return workspace.invite_code;
  }

  const inviteCode = await createUniqueInviteCode(inviteCodeExists);
  const { data, error } = await supabase
    .from('workspaces')
    .update({ invite_code: inviteCode })
    .eq('id', workspace.id)
    .select('invite_code')
    .single();

  if (error) throw error;
  return data.invite_code;
};

const readMemberships = async (userId) => {
  const { data, error } = await supabase
    .from('workspace_members')
    .select('*')
    .eq('user_id', userId)
    .eq('status', 'active')
    .order('created_at', { ascending: true });

  if (error) throw error;
  return {
    data: data || [],
    missing: false
  };
};

export const getWorkspaceOverview = async (req, res) => {
  try {
    const userId = req.user.id;
    const membershipsResult = await readMemberships(userId);

    const workspaceIds = membershipsResult.data.map((row) => row.workspace_id).filter(Boolean);
    if (!workspaceIds.length) {
      return res.status(200).json({
        mode: 'remote',
        workspaces: [],
        members: [],
        assignments: [],
        activity: []
      });
    }

    const [workspaceResult, membersResult, assignmentResult, activityResult] = await Promise.all([
      supabase.from('workspaces').select('*').in('id', workspaceIds).order('updated_at', { ascending: false }),
      supabase.from('workspace_members').select('*').in('workspace_id', workspaceIds).order('created_at', { ascending: true }),
      supabase.from('workspace_tasks').select('*').in('workspace_id', workspaceIds).order('updated_at', { ascending: false }),
      supabase
        .from('workspace_activity_events')
        .select('*')
        .in('workspace_id', workspaceIds)
        .order('created_at', { ascending: false })
        .limit(40)
    ]);

    if (membersResult.error) throw membersResult.error;
    if (assignmentResult.error) throw assignmentResult.error;
    if (activityResult.error) throw activityResult.error;
    if (workspaceResult.error) throw workspaceResult.error;

    res.status(200).json({
      mode: 'remote',
      workspaces: workspaceResult.data || [],
      members: membersResult.data || [],
      assignments: assignmentResult.data || [],
      activity: activityResult.data || []
    });
  } catch (error) {
    log('error', 'Failed to load workspace overview', {
      requestId: req.requestId,
      userId: req.user.id,
      error
    });
    res.status(500).json({
      error: 'Failed to load workspaces',
      details: error.message
    });
  }
};

export const createWorkspace = async (req, res) => {
  try {
    const userId = req.user.id;
    const name = String(req.body?.name || '').trim();
    const description = String(req.body?.description || '').trim();
    const inviteCode = await createUniqueInviteCode(inviteCodeExists);

    assert(name.length > 0, 'Workspace name is required.');

    const { data: workspace, error: workspaceError } = await supabase
      .from('workspaces')
      .insert({
        owner_user_id: userId,
        name,
        description,
        invite_code: inviteCode
      })
      .select('*')
      .single();

    if (workspaceError) throw workspaceError;

    const { error: membershipError } = await supabase.from('workspace_members').insert({
      workspace_id: workspace.id,
      user_id: userId,
      role: 'owner',
      status: 'active',
      display_name: req.user.email || 'Workspace owner'
    });

    if (membershipError) throw membershipError;

    await supabase.from('workspace_activity_events').insert({
      workspace_id: workspace.id,
      actor_user_id: userId,
      event_type: 'WORKSPACE_CREATED',
      payload: { name }
    });

    res.status(201).json({ workspace });
  } catch (error) {
    const statusCode = Number(error.statusCode || 500);
    res.status(statusCode).json({
      error: 'Failed to create workspace',
      details: error.message
    });
  }
};

export const addWorkspaceMember = async (req, res) => {
  try {
    const userId = req.user.id;
    const workspaceId = req.params.id;
    const email = String(req.body?.email || '').trim().toLowerCase();
    const role = String(req.body?.role || 'member').trim().toLowerCase();

    assert(email.length > 0, 'Member email is required.');
    assert(WORKSPACE_ROLES.has(role) && role !== 'owner', 'Workspace role is invalid.');

    await ensureWorkspaceManager(workspaceId, userId);

    const { data: userRecord, error: userError } = await supabase
      .from('users')
      .select('id, email, full_name')
      .eq('email', email)
      .maybeSingle();

    if (userError) throw userError;
    assert(Boolean(userRecord?.id), 'No existing user found for that email.', 404);

    const existingMember = await readWorkspaceMember(workspaceId, userRecord.id);
    let member = existingMember;

    if (existingMember) {
      const { data: updatedMember, error: updateError } = await supabase
        .from('workspace_members')
        .update({
          role,
          status: 'active',
          display_name: userRecord.full_name || userRecord.email,
          invited_by: userId
        })
        .eq('workspace_id', workspaceId)
        .eq('user_id', userRecord.id)
        .select('*')
        .single();

      if (updateError) throw updateError;
      member = updatedMember;
    } else {
      const { data: insertedMember, error: insertError } = await supabase
        .from('workspace_members')
        .insert({
          workspace_id: workspaceId,
          user_id: userRecord.id,
          role,
          status: 'active',
          display_name: userRecord.full_name || userRecord.email,
          invited_by: userId
        })
        .select('*')
        .single();

      if (insertError) throw insertError;
      member = insertedMember;
    }

    await supabase.from('workspace_activity_events').insert({
      workspace_id: workspaceId,
      actor_user_id: userId,
      event_type: 'MEMBER_ADDED',
      payload: {
        email,
        role
      }
    });

    res.status(201).json({ member });
  } catch (error) {
    const statusCode = Number(error.statusCode || 500);
    res.status(statusCode).json({
      error: 'Failed to add workspace member',
      details: error.message
    });
  }
};

export const assignWorkspaceTask = async (req, res) => {
  try {
    const userId = req.user.id;
    const workspaceId = req.params.id;
    const subTaskId = req.body?.subTaskId || req.body?.sub_task_id || null;
    const assigneeUserId = req.body?.assigneeUserId || req.body?.assignee_user_id || null;
    const requestedStatus = String(req.body?.status || 'active').trim().toLowerCase();

    assert(Boolean(subTaskId), 'Task id is required.');
    assert(WORKSPACE_STATUSES.has(requestedStatus), 'Workspace task status is invalid.');

    await ensureWorkspaceManager(workspaceId, userId);

    const { data: taskRow, error: taskError } = await supabase
      .from('sub_tasks')
      .select('id, title, status, user_id')
      .eq('id', subTaskId)
      .eq('user_id', userId)
      .maybeSingle();

    if (taskError) throw taskError;
    assert(Boolean(taskRow?.id), 'Task not found.', 404);

    if (assigneeUserId) {
      const assigneeMembership = await readWorkspaceMember(workspaceId, assigneeUserId);
      assert(
        Boolean(assigneeMembership && assigneeMembership.status === 'active'),
        'Assignee must be an active workspace member.',
        403
      );
    }

    const status = taskRow.status === 'completed' ? 'completed' : requestedStatus;

    const { data: assignment, error: assignmentError } = await supabase
      .from('workspace_tasks')
      .insert({
        workspace_id: workspaceId,
        sub_task_id: subTaskId,
        assignee_user_id: assigneeUserId,
        assigned_by_user_id: userId,
        status
      })
      .select('*')
      .single();

    if (assignmentError) throw assignmentError;

    await supabase.from('workspace_activity_events').insert({
      workspace_id: workspaceId,
      actor_user_id: userId,
      event_type: 'TASK_ASSIGNED',
      payload: {
        title: taskRow.title,
        assignee_user_id: assigneeUserId
      }
    });

    res.status(201).json({ assignment });
  } catch (error) {
    const statusCode = Number(error.statusCode || 500);
    res.status(statusCode).json({
      error: 'Failed to assign workspace task',
      details: error.message
    });
  }
};

export const getWorkspaceShare = async (req, res) => {
  try {
    const workspaceId = req.params.id;
    const userId = req.user.id;
    const workspace = await ensureWorkspaceManager(workspaceId, userId);
    const inviteCode = await ensureWorkspaceInviteCode(workspace);

    res.status(200).json({
      workspaceId,
      inviteCode
    });
  } catch (error) {
    const statusCode = Number(error.statusCode || 500);
    res.status(statusCode).json({
      error: 'Failed to load workspace invite code',
      details: error.message
    });
  }
};

export const joinWorkspace = async (req, res) => {
  try {
    const userId = req.user.id;
    const inviteCode = normalizeInviteCode(req.body?.inviteCode);

    assert(inviteCode.length > 0, 'Invite code is required.');

    const { data: workspace, error: workspaceError } = await supabase
      .from('workspaces')
      .select('*')
      .eq('invite_code', inviteCode)
      .maybeSingle();

    if (workspaceError) throw workspaceError;
    assert(Boolean(workspace?.id), 'Invite code was not found.', 404);

    if (workspace.owner_user_id === userId) {
      return res.status(200).json({
        workspace,
        joined: false,
        alreadyMember: true
      });
    }

    const existingMember = await readWorkspaceMember(workspace.id, userId);
    let member = existingMember;
    let joined = false;

    if (!existingMember) {
      const { data: insertedMember, error: insertError } = await supabase
        .from('workspace_members')
        .insert({
          workspace_id: workspace.id,
          user_id: userId,
          role: 'member',
          status: 'active',
          display_name: req.user.email || 'Workspace member'
        })
        .select('*')
        .single();

      if (insertError) throw insertError;
      member = insertedMember;
      joined = true;
    } else if (existingMember.status !== 'active') {
      const { data: updatedMember, error: updateError } = await supabase
        .from('workspace_members')
        .update({
          status: 'active',
          display_name: existingMember.display_name || req.user.email || 'Workspace member'
        })
        .eq('workspace_id', workspace.id)
        .eq('user_id', userId)
        .select('*')
        .single();

      if (updateError) throw updateError;
      member = updatedMember;
      joined = true;
    }

    if (joined) {
      await supabase.from('workspace_activity_events').insert({
        workspace_id: workspace.id,
        actor_user_id: userId,
        event_type: 'MEMBER_JOINED',
        payload: {
          invite_code: inviteCode,
          summary: `${req.user.email || 'A teammate'} joined via invite code.`
        }
      });
    }

    res.status(200).json({
      workspace,
      member,
      joined,
      alreadyMember: !joined
    });
  } catch (error) {
    const statusCode = Number(error.statusCode || 500);
    res.status(statusCode).json({
      error: 'Failed to join workspace',
      details: error.message
    });
  }
};

export const updateWorkspaceMember = async (req, res) => {
  try {
    const workspaceId = req.params.id;
    const memberUserId = req.params.memberUserId;
    const userId = req.user.id;
    const role = req.body?.role == null ? null : String(req.body.role).trim().toLowerCase();
    const status = req.body?.status == null ? null : String(req.body.status).trim().toLowerCase();

    const workspace = await ensureWorkspaceManager(workspaceId, userId);
    const member = await readWorkspaceMember(workspaceId, memberUserId);

    assert(Boolean(member), 'Workspace member not found.', 404);
    assert(member.role !== 'owner', 'Workspace owner cannot be edited.');
    assert(role === null || (WORKSPACE_ROLES.has(role) && role !== 'owner'), 'Workspace role is invalid.');
    assert(status === null || MEMBER_STATUSES.has(status), 'Workspace member status is invalid.');
    assert(member.user_id !== workspace.owner_user_id, 'Workspace owner cannot be edited.');
    assert(!(member.user_id === userId && status === 'removed'), 'You cannot remove yourself from the workspace.');

    const nextRole = role || member.role;
    const nextStatus = status || member.status;

    const { data: updatedMember, error: updateError } = await supabase
      .from('workspace_members')
      .update({
        role: nextRole,
        status: nextStatus
      })
      .eq('workspace_id', workspaceId)
      .eq('user_id', memberUserId)
      .select('*')
      .single();

    if (updateError) throw updateError;

    await supabase.from('workspace_activity_events').insert({
      workspace_id: workspaceId,
      actor_user_id: userId,
      event_type: nextStatus === 'removed' ? 'MEMBER_REMOVED' : 'MEMBER_UPDATED',
      payload: {
        email: updatedMember.display_name || updatedMember.user_id,
        role: nextRole,
        status: nextStatus,
        summary:
          nextStatus === 'removed'
            ? `${updatedMember.display_name || updatedMember.user_id} was removed from the workspace.`
            : `${updatedMember.display_name || updatedMember.user_id} is now ${nextRole}.`
      }
    });

    res.status(200).json({ member: updatedMember });
  } catch (error) {
    const statusCode = Number(error.statusCode || 500);
    res.status(statusCode).json({
      error: 'Failed to update workspace member',
      details: error.message
    });
  }
};
