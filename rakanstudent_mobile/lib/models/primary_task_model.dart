import 'category_model.dart';

class PrimaryTask {
  const PrimaryTask({
    required this.id,
    required this.userId,
    required this.title,
    required this.status,
    required this.taskType,
    required this.createdAt,
    this.description,
    this.dueDate,
    this.totalSubtasks,
    this.categoryId,
    this.notes,
    this.category,
  });

  final String id;
  final String userId;
  final String title;
  final String status;
  final String taskType;
  final DateTime createdAt;
  final String? description;
  final DateTime? dueDate;
  final int? totalSubtasks;
  final String? categoryId;
  final String? notes;
  final Category? category;

  factory PrimaryTask.fromJson(Map<String, dynamic> json) {
    final category = _resolveCategory(json);

    return PrimaryTask(
      id: (json['id'] ?? '').toString(),
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      status: _asNullableString(json['status']) ?? 'pending',
      taskType:
          _asNullableString(json['task_type'] ?? json['taskType']) ?? 'general',
      createdAt: _asDateTime(json['created_at'] ?? json['createdAt']),
      description: _asNullableString(json['description']),
      dueDate: _tryParseDateTime(json['due_date'] ?? json['dueDate']),
      totalSubtasks: _asNullableInt(
        json['total_subtasks'] ?? json['totalSubtasks'],
      ),
      categoryId:
          _asNullableString(json['category_id'] ?? json['categoryId']) ??
          category?.id,
      notes: _asNullableString(json['notes']),
      category: category,
    );
  }

  static Category? _resolveCategory(Map<String, dynamic> json) {
    final rawCategory = json['categories'] ?? json['category'];
    if (rawCategory is Map<String, dynamic>) {
      return Category.fromJson(rawCategory);
    }

    if (rawCategory is Map) {
      return Category.fromJson(Map<String, dynamic>.from(rawCategory));
    }

    return null;
  }

  static DateTime _asDateTime(Object? value) {
    if (value == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return DateTime.tryParse(value.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
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

  static DateTime? _tryParseDateTime(Object? value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }
}
