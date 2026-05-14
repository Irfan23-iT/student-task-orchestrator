import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/task_model.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    tz.initializeTimeZones();

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );

    await _notifications.initialize(settings);

    final androidImplementation =
        _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    await androidImplementation?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> scheduleTaskReminder(Task task) async {
    await initialize();

    if (task.isCompleted || task.dueDate == null) {
      return;
    }

    final scheduledFor =
        task.dueDate!.subtract(const Duration(minutes: 10)).toLocal();
    if (!scheduledFor.isAfter(DateTime.now())) {
      return;
    }

    await _notifications.zonedSchedule(
      task.id.hashCode.abs(),
      'Task Reminder',
      'Up next: ${task.title}',
      tz.TZDateTime.from(scheduledFor, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'task_reminders',
          'Task Reminders',
          channelDescription: 'Task reminders for upcoming mobile tasks.',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> scheduleTaskReminders(Iterable<Task> tasks) async {
    await initialize();
    for (final task in tasks) {
      try {
        await scheduleTaskReminder(task);
      } catch (error) {
        debugPrint(
          '[NotificationService] Failed to schedule reminder for ${task.id}: $error',
        );
      }
    }
  }
}
