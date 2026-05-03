class Task {
  const Task({
    required this.id,
    required this.userId,
    required this.title,
    required this.isCompleted,
    required this.createdAt,
    this.estimatedMinutes,
    this.priorityBand,
    this.priorityReason,
    this.dueDate,
  });

  final String id;
  final String userId;
  final String title;
  final bool isCompleted;
  final DateTime createdAt;
  final int? estimatedMinutes;
  final String? priorityBand;
  final String? priorityReason;
  final DateTime? dueDate;

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      isCompleted: _asBool(
        json['is_completed'] ??
            json['isCompleted'] ??
            _statusToBool(json['status']),
      ),
      createdAt: _asDateTime(json['created_at'] ?? json['createdAt']),
      estimatedMinutes: _asNullableInt(
        json['estimated_minutes'] ?? json['duration_minutes'],
      ),
      priorityBand: _asNullableString(
        json['priority_band'] ?? json['priority'],
      ),
      priorityReason: _asNullableString(json['priority_reason']),
      dueDate: _resolveDueDate(json),
    );
  }

  Task copyWith({
    String? id,
    String? userId,
    String? title,
    bool? isCompleted,
    DateTime? createdAt,
    int? estimatedMinutes,
    String? priorityBand,
    String? priorityReason,
    DateTime? dueDate,
  }) {
    return Task(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      priorityBand: priorityBand ?? this.priorityBand,
      priorityReason: priorityReason ?? this.priorityReason,
      dueDate: dueDate ?? this.dueDate,
    );
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

  static DateTime _asDateTime(Object? value) {
    if (value == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return DateTime.tryParse(value.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static bool _statusToBool(Object? value) {
    final normalized = value?.toString().toLowerCase().trim();
    return normalized == 'completed';
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

  static String? _asNullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.toString().trim();
    if (normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  static DateTime? _resolveDueDate(Map<String, dynamic> json) {
    final directDueDate = _tryParseDateTime(
      json['due_date'] ?? json['dueDate'],
    );
    if (directDueDate != null) {
      return directDueDate;
    }

    final scheduledDate = _asNullableString(json['scheduled_date']);
    if (scheduledDate == null) {
      return null;
    }

    final scheduledTime =
        _asNullableString(json['scheduled_start_time']) ?? '09:00:00';
    return _tryParseDateTime('${scheduledDate}T$scheduledTime');
  }

  static DateTime? _tryParseDateTime(Object? value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }
}
