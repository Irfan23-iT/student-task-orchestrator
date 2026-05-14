class WorkspaceOverview {
  const WorkspaceOverview({
    required this.mode,
    required this.workspaces,
    required this.members,
    required this.assignments,
    required this.activity,
  });

  final String mode;
  final List<Workspace> workspaces;
  final List<WorkspaceMember> members;
  final List<WorkspaceAssignment> assignments;
  final List<WorkspaceActivity> activity;

  factory WorkspaceOverview.fromJson(Map<String, dynamic> json) {
    return WorkspaceOverview(
      mode: _asString(json['mode'], fallback: 'remote'),
      workspaces: _asList(json['workspaces'])
          .whereType<Map<String, dynamic>>()
          .map(Workspace.fromJson)
          .toList(growable: false),
      members: _asList(json['members'])
          .whereType<Map<String, dynamic>>()
          .map(WorkspaceMember.fromJson)
          .toList(growable: false),
      assignments: _asList(json['assignments'])
          .whereType<Map<String, dynamic>>()
          .map(WorkspaceAssignment.fromJson)
          .toList(growable: false),
      activity: _asList(json['activity'])
          .whereType<Map<String, dynamic>>()
          .map(WorkspaceActivity.fromJson)
          .toList(growable: false),
    );
  }
}

class Workspace {
  const Workspace({
    required this.id,
    required this.ownerUserId,
    required this.name,
    this.description,
    this.inviteCode,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String ownerUserId;
  final String name;
  final String? description;
  final String? inviteCode;
  final String? createdAt;
  final String? updatedAt;

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: _asString(json['id']),
      ownerUserId: _asString(json['owner_user_id']),
      name: _asString(json['name'], fallback: 'Untitled workspace'),
      description: _asNullableString(json['description']),
      inviteCode: _asNullableString(json['invite_code']),
      createdAt: _asNullableString(json['created_at']),
      updatedAt: _asNullableString(json['updated_at']),
    );
  }
}

class WorkspaceMember {
  const WorkspaceMember({
    required this.id,
    required this.workspaceId,
    required this.userId,
    required this.role,
    required this.status,
    this.invitedBy,
    this.displayName,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String workspaceId;
  final String userId;
  final String role;
  final String status;
  final String? invitedBy;
  final String? displayName;
  final String? createdAt;
  final String? updatedAt;

  factory WorkspaceMember.fromJson(Map<String, dynamic> json) {
    return WorkspaceMember(
      id: _asString(json['id']),
      workspaceId: _asString(json['workspace_id']),
      userId: _asString(json['user_id']),
      role: _asString(json['role'], fallback: 'member'),
      status: _asString(json['status'], fallback: 'active'),
      invitedBy: _asNullableString(json['invited_by']),
      displayName: _asNullableString(json['display_name']),
      createdAt: _asNullableString(json['created_at']),
      updatedAt: _asNullableString(json['updated_at']),
    );
  }
}

class WorkspaceAssignment {
  const WorkspaceAssignment({
    required this.id,
    required this.workspaceId,
    required this.subTaskId,
    required this.status,
    this.assigneeUserId,
    this.assignedByUserId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String workspaceId;
  final String subTaskId;
  final String? assigneeUserId;
  final String? assignedByUserId;
  final String status;
  final String? createdAt;
  final String? updatedAt;

  factory WorkspaceAssignment.fromJson(Map<String, dynamic> json) {
    return WorkspaceAssignment(
      id: _asString(json['id']),
      workspaceId: _asString(json['workspace_id']),
      subTaskId: _asString(json['sub_task_id']),
      assigneeUserId: _asNullableString(json['assignee_user_id']),
      assignedByUserId: _asNullableString(json['assigned_by_user_id']),
      status: _asString(json['status'], fallback: 'active'),
      createdAt: _asNullableString(json['created_at']),
      updatedAt: _asNullableString(json['updated_at']),
    );
  }
}

class WorkspaceActivity {
  const WorkspaceActivity({
    required this.id,
    required this.workspaceId,
    required this.eventType,
    required this.payload,
    this.actorUserId,
    this.createdAt,
  });

  final int id;
  final String workspaceId;
  final String? actorUserId;
  final String eventType;
  final Map<String, dynamic> payload;
  final String? createdAt;

  factory WorkspaceActivity.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];

    return WorkspaceActivity(
      id: _asInt(json['id']),
      workspaceId: _asString(json['workspace_id']),
      actorUserId: _asNullableString(json['actor_user_id']),
      eventType: _asString(json['event_type']),
      payload:
          rawPayload is Map<String, dynamic> ? rawPayload : <String, dynamic>{},
      createdAt: _asNullableString(json['created_at']),
    );
  }
}

List<dynamic> _asList(Object? value) {
  return value is List ? value : const <dynamic>[];
}

String _asString(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }

  final stringValue = value.toString().trim();
  return stringValue.isEmpty ? fallback : stringValue;
}

String? _asNullableString(Object? value) {
  if (value == null) {
    return null;
  }

  final stringValue = value.toString().trim();
  return stringValue.isEmpty ? null : stringValue;
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}
