import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakanstudent_mobile/features/home/dashboard_view.dart';
import 'package:rakanstudent_mobile/models/class_model.dart';
import 'package:rakanstudent_mobile/services/api_service.dart';

class _DashboardScheduleState {
  List<ClassModel> fixedClasses = const <ClassModel>[];

  Future<DashboardSummaryDto> fetchDashboardSummary() async {
    return DashboardSummaryDto.fromJson({
      'pendingTasksCount': 0,
      'classesTodayCount': fixedClasses.length,
      'nextClassName': 'No classes today',
    });
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
    await tester.pumpAndSettle();

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

    await tester.pumpAndSettle();

    expect(find.text('Software Quality'), findsOneWidget);
  });
}
