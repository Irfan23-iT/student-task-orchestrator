import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakanstudent_mobile/features/coach/coach_view.dart';

void main() {
  testWidgets('Coach view recommends the highest-risk task', (tester) async {
    final now = DateTime.now();
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CoachView(
          fetchTasks: () async {
            return [
              {
                'id': 'low-risk',
                'user_id': 'user-1',
                'title': 'Read optional article',
                'status': 'pending',
                'is_completed': false,
                'created_at':
                    now.subtract(const Duration(days: 2)).toIso8601String(),
                'due_date': now.add(const Duration(days: 8)).toIso8601String(),
                'priority_band': 'Low',
              },
              {
                'id': 'urgent-risk',
                'user_id': 'user-1',
                'title': 'Submit database assignment',
                'status': 'pending',
                'is_completed': false,
                'created_at':
                    now.subtract(const Duration(days: 1)).toIso8601String(),
                'due_date': now.add(const Duration(hours: 8)).toIso8601String(),
                'priority_band': 'High',
                'estimated_minutes': 45,
                'notes': 'Finish SQL joins and database schema questions.',
              },
            ];
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Study Coach'), findsOneWidget);
    expect(find.text('RAKAN COMMAND CENTER'), findsOneWidget);
    expect(find.text('Mission Mode'), findsOneWidget);
    expect(find.text('Deadline rescue'), findsOneWidget);
    expect(find.text('Deep work'), findsOneWidget);
    expect(find.text('Quick win'), findsOneWidget);
    expect(find.text('Moodle Calendar'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('ICS file'), findsOneWidget);
    expect(find.text('Assignments'), findsOneWidget);
    expect(find.text('Choose What To Coach'), findsOneWidget);
    expect(find.text('Submit database assignment'), findsWidgets);
    expect(find.text('Step-by-Step Coach'), findsOneWidget);
    expect(find.text('Moodle deliverables'), findsOneWidget);
    expect(
      find.textContaining('problem-solving task | due within 24 hours'),
      findsOneWidget,
    );
    expect(find.textContaining('focus: SQL, database, schema'), findsOneWidget);
    expect(find.textContaining('STEP 1 OF'), findsOneWidget);
    expect(find.text('OUTPUT BEFORE MOVING ON'), findsOneWidget);
    expect(find.textContaining('SQL queries'), findsWidgets);
    expect(find.text('Next Step'), findsOneWidget);
    expect(find.text('FULL BREAKDOWN'), findsOneWidget);
    expect(find.text('Map Deliverables'), findsWidgets);

    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next Step'));
    await tester.pumpAndSettle();
    expect(find.textContaining('STEP 2 OF'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('After This'), findsOneWidget);
  });

  testWidgets('Coach breaks Moodle assignment into deliverables', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CoachView(
          fetchTasks: () async {
            return [
              {
                'id': 'moodle-db-project',
                'user_id': 'user-1',
                'title': 'Database Project',
                'status': 'pending',
                'is_completed': false,
                'created_at': now.toIso8601String(),
                'due_date': now.add(const Duration(days: 2)).toIso8601String(),
                'priority_band': 'High',
                'estimated_minutes': 120,
                'task_type': 'moodle',
                'notes':
                    'Imported from Moodle assignments.\nCourse: Database Systems\nSubmit schema, ERD diagram, SQL queries, and final report.',
              },
            ];
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Moodle deliverables'), findsOneWidget);
    expect(find.textContaining('deliverables: ERD diagram'), findsWidgets);
    expect(find.text('Map Deliverables'), findsWidgets);
    expect(find.text('ERD Diagram'), findsOneWidget);
    expect(find.text('Schema'), findsOneWidget);
    expect(find.text('SQL Queries'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
  });

  testWidgets('Coach reviews Moodle feedback instead of reworking submission', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CoachView(
          fetchTasks: () async {
            return [
              {
                'id': 'graded-moodle-task',
                'user_id': 'user-1',
                'title': 'Database Project Feedback',
                'status': 'pending',
                'is_completed': false,
                'created_at': now.toIso8601String(),
                'due_date': now.add(const Duration(days: 1)).toIso8601String(),
                'priority_band': 'Medium',
                'task_type': 'moodle',
                'notes':
                    'Imported from Moodle assignments.\nCourse: Database Systems\nSubmission status: submitted\nGrade: 82 / 100\nFeedback: Explain your schema assumptions.',
              },
            ];
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Feedback review'), findsOneWidget);
    expect(find.text('Read Feedback'), findsWidgets);
    expect(
      find.textContaining('Explain your schema assumptions'),
      findsWidgets,
    );
    expect(find.text('Extract Rule'), findsOneWidget);
  });
}
