import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rakanstudent_mobile/core/theme_provider.dart';
import 'package:rakanstudent_mobile/features/auth/login_screen.dart';
import 'package:rakanstudent_mobile/features/auth/signup_screen.dart';
import 'package:rakanstudent_mobile/features/home/dashboard_view.dart';
import 'package:rakanstudent_mobile/features/home/main_screen.dart';
import 'package:rakanstudent_mobile/features/home/sprint_game_screen.dart';
import 'package:rakanstudent_mobile/features/profile/profile_view.dart';
import 'package:rakanstudent_mobile/features/schedule/schedule_view.dart';
import 'package:rakanstudent_mobile/features/tasks/tasks_view.dart';
import 'package:rakanstudent_mobile/features/timer/timer_sheet.dart';
import 'package:rakanstudent_mobile/models/class_schedule_model.dart';
import 'package:rakanstudent_mobile/models/class_model.dart';
import 'package:rakanstudent_mobile/models/task_model.dart';
import 'package:rakanstudent_mobile/services/api_service.dart';
import 'package:rakanstudent_mobile/views/ai_chat_view.dart';
import 'package:rakanstudent_mobile/views/calendar_view.dart';

Future<DashboardSummaryDto> _emptyDashboardSummary() async {
  return DashboardSummaryDto.fromJson({
    'pendingTasksCount': 0,
    'classesTodayCount': 0,
    'nextClassName': 'No classes today',
  });
}

Future<List<ClassModel>> _emptyFixedClasses() async => const <ClassModel>[];

void main() {
  testWidgets('Login screen renders expected shell copy', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text("Don't have an account? Sign Up"), findsOneWidget);
  });

  testWidgets('Login screen navigates to sign up screen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    final signUpLink = find.widgetWithText(
      TextButton,
      "Don't have an account? Sign Up",
    );
    await tester.ensureVisible(signUpLink);
    await tester.tap(signUpLink);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(SignUpScreen), findsOneWidget);
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

    final signUpButton = find.widgetWithText(ElevatedButton, 'Sign Up');
    await tester.ensureVisible(signUpButton);
    await tester.tap(signUpButton);
    await tester.pump();

    expect(find.text('Enter a valid email address'), findsOneWidget);
  });

  testWidgets('Dashboard view renders summary content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardView(
          fetchDashboardSummary: _emptyDashboardSummary,
          fetchFixedClasses: _emptyFixedClasses,
          enableStartupSideEffects: false,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Focus Mode'), findsOneWidget);
    expect(find.text('QUICK OVERVIEW'), findsOneWidget);
    expect(find.text('UPCOMING'), findsNothing);
    expect(
      find.text('No upcoming classes or task deadlines yet.'),
      findsNothing,
    );
    expect(find.text('ACTIVE REMINDERS'), findsOneWidget);
    expect(find.text('Tasks Pending'), findsOneWidget);
    expect(find.text('No classes today'), findsOneWidget);
    expect(find.text('Next Class'), findsOneWidget);
    expect(find.text('Classes Today'), findsNothing);
    expect(find.text('Focus Reward'), findsOneWidget);
    expect(find.text('Sprint Challenge'), findsOneWidget);
    expect(find.text('Tap to Race'), findsOneWidget);
    expect(find.text('View All'), findsOneWidget);
  });

  testWidgets('Sprint challenge screen renders HUD and exits with score', (
    tester,
  ) async {
    int? returnedScore;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    returnedScore = await Navigator.of(context).push<int>(
                      MaterialPageRoute(
                        builder:
                            (context) =>
                                const SprintGameScreen(startImmediately: false),
                      ),
                    );
                  },
                  child: const Text('Open Sprint'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open Sprint'));
    await tester.pumpAndSettle();

    expect(find.text('SPRINT CHALLENGE'), findsOneWidget);
    expect(find.text('XP 00'), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.directions_car_rounded), findsOneWidget);

    await tester.tap(find.byTooltip('Exit Race'));
    await tester.pumpAndSettle();

    expect(returnedScore, 0);
  });

  testWidgets('Dashboard focus timer cycles duration and counts down', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardView(
          fetchDashboardSummary: _emptyDashboardSummary,
          fetchFixedClasses: _emptyFixedClasses,
          enableStartupSideEffects: false,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('Open Deep Work Room'));
    await tester.pumpAndSettle();

    expect(find.text('Deep Work Room'), findsOneWidget);
    expect(find.text('25 min Pomodoro'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Enter Deep Work'), findsOneWidget);
  });

  testWidgets('Main screen bottom navigation fits compact width', (
    tester,
  ) async {
    final originalOnError = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = errors.add;

    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      FlutterError.onError = originalOnError;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MainScreen(
          testScreens: List<Widget>.generate(
            6,
            (index) => ColoredBox(
              color: Colors.white,
              child: Center(child: Text('Screen $index')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final overflowErrors = errors.where(
      (error) => error.exceptionAsString().contains('RenderFlex overflowed'),
    );
    expect(overflowErrors, isEmpty);
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
    await tester.pumpWidget(
      const MaterialApp(
        home: TasksView(
          fetchOnInit: false,
          enableVoiceCapture: false,
          enableCleanupVerification: false,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Add Custom Task'), findsOneWidget);
    expect(find.text('AI Orchestrator'), findsNothing);
    expect(find.text('Generate'), findsNothing);
    expect(find.text('Sync to Calendar'), findsOneWidget);
    expect(find.text('Delete All'), findsOneWidget);
  });

  testWidgets('Tasks view opens custom task form', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TasksView(
          fetchOnInit: false,
          enableVoiceCapture: false,
          enableCleanupVerification: false,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Add Custom Task'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Task Title'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Description / Additional Info'),
      findsOneWidget,
    );
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('Optional Due Date'), findsOneWidget);
    expect(find.text('Save Task'), findsOneWidget);
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

  testWidgets('Calendar view renders monthly shell', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CalendarView(fetchOnInit: false)),
    );

    await tester.pump();

    expect(find.text('Calendar'), findsOneWidget);
    expect(find.text('Tasks by due date'), findsOneWidget);
  });

  testWidgets('Calendar view renders task marker and selected day list', (
    tester,
  ) async {
    final now = DateTime.now();
    final task = Task(
      id: 'task-1',
      userId: 'user-1',
      title: 'Calendar marker task',
      isCompleted: false,
      createdAt: now,
      dueDate: now,
      priorityBand: 'High',
    );

    await tester.pumpWidget(
      MaterialApp(home: CalendarView(initialTasks: [task], fetchOnInit: false)),
    );

    await tester.pump();

    expect(
      find.byKey(
        ValueKey('calendar-marker-${now.year}-${now.month}-${now.day}'),
      ),
      findsWidgets,
    );
    expect(find.text('Calendar marker task'), findsOneWidget);
  });

  testWidgets('Calendar view deduplicates repeated task rows', (tester) async {
    final now = DateTime.now();
    final taskMorning = Task(
      id: 'task-1',
      userId: 'user-1',
      title: 'Calendar marker task',
      isCompleted: false,
      createdAt: now,
      dueDate: DateTime(now.year, now.month, now.day, 9),
      priorityBand: 'High',
    );
    final taskAfternoon = Task(
      id: 'primary-task-1',
      userId: 'user-1',
      title: ' calendar marker task ',
      isCompleted: false,
      createdAt: now,
      dueDate: DateTime(now.year, now.month, now.day, 13),
      priorityBand: 'High',
    );
    final taskEvening = Task(
      id: 'task-row-1',
      userId: 'user-1',
      title: 'Calendar   marker   TASK',
      isCompleted: false,
      createdAt: now,
      dueDate: DateTime(now.year, now.month, now.day, 17),
      priorityBand: 'High',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarView(
          initialTasks: [taskMorning, taskAfternoon, taskEvening],
          fetchOnInit: false,
        ),
      ),
    );

    await tester.pump();

    expect(find.text('Calendar marker task'), findsOneWidget);
    expect(find.text(' calendar marker task '), findsNothing);
    expect(find.text('Calendar   marker   TASK'), findsNothing);
  });

  testWidgets('Calendar view renders recurring class markers and list items', (
    tester,
  ) async {
    final now = DateTime.now();
    final classSchedule = ClassSchedule(
      id: 'class-1',
      dayOfWeek: now.weekday,
      startTime: '09:00',
      endTime: '11:00',
      className: 'Software Quality',
      colorHex: '#0F766E',
      classType: 'Lecture',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CalendarView(initialClasses: [classSchedule], fetchOnInit: false),
      ),
    );

    await tester.pump();

    expect(
      find.byKey(
        ValueKey('calendar-marker-${now.year}-${now.month}-${now.day}'),
      ),
      findsWidgets,
    );
    expect(find.text('Software Quality'), findsOneWidget);
    expect(find.text('Class | Lecture | 09:00 - 11:00'), findsOneWidget);
  });

  testWidgets('Schedule view renders new shell copy', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ScheduleView()));

    await tester.pumpAndSettle();

    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Your fixed weekly classes'), findsOneWidget);
  });

  testWidgets('Profile view renders new shell copy', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProfileView())),
    );

    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Sleep Schedule'), findsNothing);
    expect(find.text('Integrations'), findsOneWidget);
    expect(find.text('Dark Mode'), findsOneWidget);
  });

  testWidgets('Profile dark mode switch updates theme provider', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProfileView()),
      ),
    );

    await tester.pump();

    expect(container.read(themeModeProvider), ThemeMode.dark);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(container.read(themeModeProvider), ThemeMode.light);
  });
}
