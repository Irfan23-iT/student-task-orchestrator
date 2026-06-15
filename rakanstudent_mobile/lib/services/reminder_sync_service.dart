import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'notification_service.dart';

class ReminderSyncService {
  ReminderSyncService._();

  static final ReminderSyncService instance = ReminderSyncService._();

  Timer? _pollTimer;
  bool _isSyncing = false;
  final Set<String> _scheduledReminderIds = {};

  static const _pollInterval = Duration(minutes: 5);

  void startPeriodicSync() {
    stopPeriodicSync();
    _syncNow();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _syncNow());
  }

  void stopPeriodicSync() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> syncNow() => _syncNow();

  Future<void> _syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final apiService = ApiService();
      final reminders = await apiService.listReminders(status: 'scheduled');

      final notificationService = NotificationService.instance;
      final currentIds = <String>{};

      for (final reminder in reminders) {
        final id = reminder['id'] as String?;
        final title = reminder['title'] as String?;
        final reminderAtStr = reminder['reminder_at'] as String?;

        if (id == null || title == null || reminderAtStr == null) continue;

        final reminderAt = DateTime.tryParse(reminderAtStr);
        if (reminderAt == null) continue;

        currentIds.add(id);

        if (_scheduledReminderIds.contains(id)) continue;

        final notificationId = id.hashCode.abs() % 2147483647;
        await notificationService.scheduleReminder(
          id: notificationId,
          title: title,
          scheduledAt: reminderAt,
        );
        _scheduledReminderIds.add(id);
        debugPrint('[ReminderSyncService] Scheduled reminder: $title at $reminderAt');
      }

      final removedIds = _scheduledReminderIds.difference(currentIds);
      for (final id in removedIds) {
        final notificationId = id.hashCode.abs() % 2147483647;
        await notificationService.cancelReminder(notificationId);
        _scheduledReminderIds.remove(id);
        debugPrint('[ReminderSyncService] Cancelled reminder: $id');
      }
    } catch (e) {
      debugPrint('[ReminderSyncService] Sync failed: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
