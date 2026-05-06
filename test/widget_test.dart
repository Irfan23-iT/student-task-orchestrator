import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rakanstudent_mobile/features/auth/login_screen.dart';
import 'package:rakanstudent_mobile/features/auth/signup_screen.dart';
import 'package:rakanstudent_mobile/features/home/dashboard_view.dart';
import 'package:rakanstudent_mobile/features/profile/profile_view.dart';
import 'package:rakanstudent_mobile/features/schedule/schedule_view.dart';
import 'package:rakanstudent_mobile/features/tasks/tasks_view.dart';
import 'package:rakanstudent_mobile/features/timer/timer_sheet.dart';
import 'package:rakanstudent_mobile/views/ai_chat_view.dart';

void main() {
  testWidgets('Login screen renders expected shell copy', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text("Don't have an account? Sign Up"), findsOneWidget);
  });

  testWidgets('Login screen navigates to sign up screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.text("Don't have an account? Sign Up"));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
  });

  testWidgets('Sign up screen validates email before submitting', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));

    await tester.enterText(find.byType(TextFormField).at(0), 'invalid-email');
    await tester.enterText(find.byType(TextFormField).at(1), 'abc12345');
    await tester.enterText(find.byType(TextFormField).at(2), 'abc12345');

    await tester.tap(find.text('Sign Up'));
    await tester.pump();

    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('Dashboard view renders summary content', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DashboardView()));

    await tester.pumpAndSettle();

    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Focus Mode'), findsOneWidget);
    expect(find.text('QUICK OVERVIEW'), findsOneWidget);
    expect(find.text('ACTIVE REMINDERS'), findsOneWidget);
    expect(find.text('Tasks Pending'), findsOneWidget);
    expect(find.text('No classes scheduled'), findsOneWidget);
    expect(find.text('View All'), findsOneWidget);
  });

  testWidgets('Timer sheet renders controls and automated test runs', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TimerSheet(enableCodexTimerTest: true)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.text('Pomodoro Timer'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);
  });

  testWidgets('Tasks view renders new shell controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TasksView()));

    await tester.pumpAndSettle();

    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('AI Orchestrator'), findsOneWidget);
    expect(find.text('Generate'), findsOneWidget);
    expect(find.text('Sync to Calendar'), findsOneWidget);
    expect(find.text('Delete All'), findsOneWidget);
  });

  testWidgets('AI chat view renders chat input', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AiChatView()));

    expect(find.text('AI Chat'), findsOneWidget);
    expect(
      find.text('Ask me about today, priorities, or what to tackle next.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'What do I have to do today?'),
      findsOneWidget,
    );
  });

  testWidgets('Schedule view renders new shell copy', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ScheduleView()));

    await tester.pumpAndSettle();

    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Your fixed weekly classes'), findsOneWidget);
  });

  testWidgets('Profile view renders new shell copy', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProfileView()));

    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Sleep Schedule'), findsOneWidget);
    expect(find.text('Integrations'), findsOneWidget);
  });
}
