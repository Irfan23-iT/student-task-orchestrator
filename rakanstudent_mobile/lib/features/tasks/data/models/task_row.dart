class TaskRow {
  const TaskRow({
    required this.id,
    required this.title,
    required this.status,
    this.parentTaskId,
    this.estimatedMinutes,
    this.isChunked = false,
    this.scheduledDate,
    this.scheduledStartTime,
    this.scheduledEndTime,
    this.pipelineRunId,
    this.clientTaskKey,
    this.primaryTaskId,
    this.priorityScore,
    this.priorityBand,
    this.priorityReason,
    this.manualPriorityOverride = false,
    this.userId,
  });

  final String id;
  final String title;
  final String status;
  final String? parentTaskId;
  final int? estimatedMinutes;
  final bool isChunked;
  final String? scheduledDate;
  final String? scheduledStartTime;
  final String? scheduledEndTime;
  final String? pipelineRunId;
  final String? clientTaskKey;
  final String? primaryTaskId;
  final int? priorityScore;
  final String? priorityBand;
  final String? priorityReason;
  final bool manualPriorityOverride;
  final String? userId;

  factory TaskRow.fromJson(Map<String, dynamic> json) {
    return TaskRow(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      parentTaskId: _asNullableString(json['parent_task_id']),
      estimatedMinutes: _asNullableInt(json['estimated_minutes']),
      isChunked: _asBool(json['is_chunked']),
      scheduledDate: _asNullableString(json['scheduled_date']),
      scheduledStartTime: _asNullableString(json['scheduled_start_time']),
      scheduledEndTime: _asNullableString(json['scheduled_end_time']),
      pipelineRunId: _asNullableString(json['pipeline_run_id']),
      clientTaskKey: _asNullableString(json['client_task_key']),
      primaryTaskId: _asNullableString(json['primary_task_id']),
      priorityScore: _asNullableInt(json['priority_score']),
      priorityBand: _asNullableString(json['priority_band']),
      priorityReason: _asNullableString(json['priority_reason']),
      manualPriorityOverride: _asBool(json['manual_priority_override']),
      userId: _asNullableString(json['user_id']),
    );
  }

  String get scheduleLabel {
    if (scheduledDate == null ||
        scheduledStartTime == null ||
        scheduledEndTime == null) {
      return 'Unscheduled';
    }

    return '$scheduledDate | $scheduledStartTime-$scheduledEndTime';
  }

  static String? _asNullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final stringValue = value.toString().trim();
    return stringValue.isEmpty ? null : stringValue;
  }

  static int? _asNullableInt(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(value.toString());
  }

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final normalized = value?.toString().toLowerCase().trim();
    return normalized == 'true' || normalized == '1';
  }
}
