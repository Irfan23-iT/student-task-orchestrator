import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakanstudent_mobile/features/home/dashboard_view.dart';
import 'package:rakanstudent_mobile/models/class_model.dart';
import 'package:rakanstudent_mobile/services/api_service.dart';

class _DashboardScheduleState {
  List<ClassModel> fixedClasses = const <ClassModel>[];
  DashboardSummaryDto summary = DashboardSummaryDto.fromJson({
    'pendingTasksCount': 0,
    'classesTodayCount': 0,
    'nextClassName': 'No classes today',
  });

  Future<DashboardSummaryDto> fetchDashboardSummary() async {
    return summary;
  }

  Future<List<ClassModel>> fetchFixedClasses() async => fixedClasses;
}

void main() {
  testWidgets('Dashboard Next Class container updates when schedule mutates', (
    tester,
  ) async {
    final scheduleState = _DashboardScheduleState();

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardView(
          fetchDashboardSummary: scheduleState.fetchDashboardSummary,
          fetchFixedClasses: scheduleState.fetchFixedClasses,
          enableStartupSideEffects: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('No classes today'), findsOneWidget);

    final now = DateTime.now();
    scheduleState.fixedClasses = [
      ClassModel(
        id: 'class-1',
        dayOfWeek: now.weekday,
        startTime: '00:00:00',
        endTime: '23:59:00',
        className: 'Software Quality',
        classType: 'Lecture',
      ),
    ];
    ApiService.scheduleMutationNotifier.value++;

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('Software Quality'), findsOneWidget);
  });

  testWidgets('Dashboard Tasks Pending container uses active reminders count', (
    tester,
  ) async {
    final dashboardState =
        _DashboardScheduleState()
          ..summary = DashboardSummaryDto.fromJson({
            'pendingTasksCount': 1,
            'upcomingBlocks': [
              {
                'id': 'voice-task-1',
                'title': 'Software Quality homework',
                'startsAt': '2026-05-18T09:00:00Z',
                'priority': 'High',
              },
              {
                'id': 'voice-task-2',
                'title': 'Read chapter four',
                'startsAt': '2026-05-18T10:00:00Z',
                'priority': 'Medium',
              },
              {
                'id': 'voice-task-3',
                'title': 'Prepare lab notes',
                'startsAt': '2026-05-18T11:00:00Z',
                'priority': 'Low',
              },
            ],
          });

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardView(
          fetchDashboardSummary: dashboardState.fetchDashboardSummary,
          fetchFixedClasses: dashboardState.fetchFixedClasses,
          enableStartupSideEffects: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Tasks Pending'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Software Quality homework'), findsOneWidget);
    expect(find.text('Read chapter four'), findsOneWidget);
    expect(find.text('Prepare lab notes'), findsOneWidget);
  });
}
