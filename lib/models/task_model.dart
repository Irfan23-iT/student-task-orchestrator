class Task {
  const Task({
    required this.id,
    required this.userId,
    required this.title,
    required this.isCompleted,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String title;
  final bool isCompleted;
  final DateTime createdAt;

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
    );
  }

  Task copyWith({
    String? id,
    String? userId,
    String? title,
    bool? isCompleted,
    DateTime? createdAt,
  }) {
    return Task(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
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
}
