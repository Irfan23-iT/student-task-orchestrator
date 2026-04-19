class AnalyticsModel {
  const AnalyticsModel({
    required this.streakSnapshot,
    required this.reminderJobs,
    required this.userBadges,
    required this.notificationPreferences,
  });

  final Map<String, dynamic> streakSnapshot;
  final List<ReminderJobModel> reminderJobs;
  final List<UserBadgeModel> userBadges;
  final NotificationPreferencesModel notificationPreferences;

  int get currentStreak => _asInt(streakSnapshot['currentStreak']);

  factory AnalyticsModel.fromJson(Map<String, dynamic> json) {
    final rawStreak =
        (json['streakSnapshot'] as Map<String, dynamic>?) ?? const {};
    final normalizedStreak = <String, dynamic>{
      ...rawStreak,
      'currentStreak':
          rawStreak['currentStreak'] ??
          rawStreak['streakCount'] ??
          rawStreak['streak_count'] ??
          0,
      'longestStreak':
          rawStreak['longestStreak'] ?? rawStreak['longest_streak'] ?? 0,
    };

    final rawBadges = json['userBadges'] as List<dynamic>? ?? const [];
    final rawReminderJobs = json['reminderJobs'] as List<dynamic>? ?? const [];

    return AnalyticsModel(
      streakSnapshot: normalizedStreak,
      reminderJobs: rawReminderJobs
          .whereType<Map<String, dynamic>>()
          .map(ReminderJobModel.fromJson)
          .toList(growable: false),
      userBadges: rawBadges
          .whereType<Map<String, dynamic>>()
          .map(UserBadgeModel.fromJson)
          .toList(growable: false),
      notificationPreferences: NotificationPreferencesModel.fromJson(
        (json['notificationPreferences'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse('${value ?? ''}') ?? 0;
  }
}

class ReminderJobModel {
  const ReminderJobModel({
    required this.id,
    required this.subTaskId,
    required this.title,
    required this.reminderAt,
    required this.channel,
    required this.status,
  });

  final String id;
  final String? subTaskId;
  final String title;
  final DateTime reminderAt;
  final String channel;
  final String status;

  factory ReminderJobModel.fromJson(Map<String, dynamic> json) {
    return ReminderJobModel(
      id: (json['id'] ?? '').toString(),
      subTaskId: _optionalString(json['sub_task_id'] ?? json['subTaskId']),
      title: (json['title'] ?? 'Reminder').toString(),
      reminderAt: _asDateTime(
        json['reminder_at'] ?? json['reminderAt'] ?? json['created_at'],
      ),
      channel: (json['channel'] ?? 'email').toString(),
      status: (json['status'] ?? 'scheduled').toString(),
    );
  }

  static DateTime _asDateTime(Object? value) {
    if (value == null) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return DateTime.tryParse(value.toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static String? _optionalString(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return normalized.isEmpty ? null : normalized;
  }
}

class UserBadgeModel {
  const UserBadgeModel({
    required this.id,
    required this.badgeId,
    required this.badgeKey,
  });

  final String id;
  final String badgeId;
  final String badgeKey;

  factory UserBadgeModel.fromJson(Map<String, dynamic> json) {
    final payload = (json['payload'] as Map<String, dynamic>?) ?? const {};

    return UserBadgeModel(
      id: (json['id'] ?? '').toString(),
      badgeId: (json['badge_id'] ?? json['badgeId'] ?? '').toString(),
      badgeKey:
          (payload['badge_key'] ??
                  json['badge_key'] ??
                  json['badgeKey'] ??
                  json['badge_id'] ??
                  json['badgeId'] ??
                  'badge')
              .toString(),
    );
  }
}

class NotificationPreferencesModel {
  const NotificationPreferencesModel({
    required this.inboxEnabled,
    required this.emailEnabled,
    required this.reminderLeadMinutes,
    required this.quietHoursStart,
    required this.quietHoursEnd,
    required this.timeZone,
  });

  final bool inboxEnabled;
  final bool emailEnabled;
  final int reminderLeadMinutes;
  final String quietHoursStart;
  final String quietHoursEnd;
  final String timeZone;

  factory NotificationPreferencesModel.fromJson(Map<String, dynamic> json) {
    return NotificationPreferencesModel(
      inboxEnabled: _asBool(
        json['inboxEnabled'] ?? json['inbox_enabled'] ?? true,
      ),
      emailEnabled: _asBool(
        json['emailEnabled'] ?? json['email_enabled'] ?? false,
      ),
      reminderLeadMinutes: _asInt(
        json['reminderLeadMinutes'] ?? json['reminder_lead_minutes'] ?? 30,
      ),
      quietHoursStart:
          (json['quietHoursStart'] ?? json['quiet_hours_start'] ?? '22:00')
              .toString(),
      quietHoursEnd:
          (json['quietHoursEnd'] ?? json['quiet_hours_end'] ?? '07:00')
              .toString(),
      timeZone: (json['timeZone'] ?? json['time_zone'] ?? 'UTC').toString(),
    );
  }

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final normalized = value?.toString().toLowerCase().trim();
    return normalized == 'true' || normalized == '1';
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
