import 'package:flutter_test/flutter_test.dart';
import 'package:rakanstudent_mobile/models/category_model.dart';
import 'package:rakanstudent_mobile/models/primary_task_model.dart';
import 'package:rakanstudent_mobile/models/task_model.dart';

void main() {
  test('Category normalizes hex colors for UI use', () {
    final category = Category.fromJson({
      'id': 'category-1',
      'user_id': 'user-1',
      'name': 'Coursework',
      'color_hex': '2563eb',
    });

    expect(category.colorHex, '#2563EB');
  });

  test('Task maps taxonomy fields and nested category payload', () {
    final task = Task.fromJson({
      'id': 'task-1',
      'user_id': 'user-1',
      'title': 'Read chapter 4',
      'status': 'in_progress',
      'task_type': 'assignment',
      'category_id': 'category-1',
      'notes': 'Focus on examples.',
      'created_at': '2026-05-11T12:00:00.000Z',
      'categories': {
        'id': 'category-1',
        'user_id': 'user-1',
        'name': 'Coursework',
        'color_hex': '#0f766e',
      },
    });

    expect(task.status, 'in_progress');
    expect(task.taskType, 'assignment');
    expect(task.categoryId, 'category-1');
    expect(task.notes, 'Focus on examples.');
    expect(task.category?.name, 'Coursework');
    expect(task.category?.colorHex, '#0F766E');
  });

  test('PrimaryTask maps taxonomy fields and nested category payload', () {
    final primaryTask = PrimaryTask.fromJson({
      'id': 'primary-1',
      'user_id': 'user-1',
      'title': 'Final exam prep',
      'status': 'pending',
      'task_type': 'exam',
      'category_id': 'category-2',
      'notes': 'Revise past papers.',
      'created_at': '2026-05-11T12:00:00.000Z',
      'categories': {
        'id': 'category-2',
        'user_id': 'user-1',
        'name': 'Exams',
        'color_hex': '#dc2626',
      },
    });

    expect(primaryTask.status, 'pending');
    expect(primaryTask.taskType, 'exam');
    expect(primaryTask.categoryId, 'category-2');
    expect(primaryTask.notes, 'Revise past papers.');
    expect(primaryTask.category?.name, 'Exams');
    expect(primaryTask.category?.colorHex, '#DC2626');
  });
}
