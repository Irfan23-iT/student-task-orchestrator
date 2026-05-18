import 'package:flutter_test/flutter_test.dart';
import 'package:rakanstudent_mobile/models/class_model.dart';
import 'package:rakanstudent_mobile/services/api_service.dart';

void main() {
  test('task-only upcoming blocks do not populate next class fields', () {
    final summary = DashboardSummaryDto.fromJson({
      'tasks': [
        {'id': 'task-1', 'title': 'Read chapter 4', 'type': 'task'},
      ],
      'upcomingBlocks': [
        {
          'id': 'reminder-1',
          'title': 'Read chapter 4',
          'startsAt': '2026-05-18T09:00:00Z',
          'priority': 'high',
        },
      ],
    });

    expect(summary.pendingTasksCount, 1);
    expect(summary.classesTodayCount, 0);
    expect(summary.nextClassTitle, 'No classes today');
    expect(summary.nextClassDetail, 'Next Class');
  });

  test('explicit next class fields stay separate from pending tasks', () {
    final summary = DashboardSummaryDto.fromJson({
      'pendingTasksCount': 3,
      'classesTodayCount': 1,
      'nextClassName': 'Software Quality',
      'nextClassSubtitle': '9:00 AM - 11:00 AM',
      'upcomingBlocks': [
        {
          'id': 'reminder-1',
          'title': 'Submit assignment',
          'startsAt': '2026-05-18T08:00:00Z',
          'priority': 'medium',
        },
      ],
    });

    expect(summary.pendingTasksCount, 3);
    expect(summary.classesTodayCount, 1);
    expect(summary.nextClassTitle, 'Software Quality');
    expect(summary.nextClassDetail, '9:00 AM - 11:00 AM');
  });

  test('next class title is derived from upcoming fixed classes today', () {
    final now = DateTime.now();
    final summary = DashboardSummaryDto.fromJson({
      'pendingTasksCount': 2,
      'nextClassName': 'Stale API Class',
    }).copyWith(
      fixedClasses: [
        ClassModel(
          id: 'class-1',
          dayOfWeek: now.weekday,
          startTime: '00:00:00',
          endTime: '23:59:00',
          className: 'Software Quality',
          classType: 'Lecture',
        ),
      ],
    );

    expect(summary.pendingTasksCount, 2);
    expect(summary.nextClassTitle, 'Software Quality');
  });

  test(
    'next class title ignores fixed classes that are not upcoming today',
    () {
      final now = DateTime.now();
      final tomorrow = now.weekday == 7 ? 1 : now.weekday + 1;
      final summary = DashboardSummaryDto.fromJson({
        'nextClassName': 'Stale API Class',
      }).copyWith(
        fixedClasses: [
          ClassModel(
            id: 'class-1',
            dayOfWeek: tomorrow,
            startTime: '09:00:00',
            endTime: '10:00:00',
            className: 'Tomorrow Class',
            classType: 'Lecture',
          ),
        ],
      );

      expect(summary.nextClassTitle, 'No classes today');
      expect(summary.nextClassDetail, 'Next Class');
    },
  );
}
