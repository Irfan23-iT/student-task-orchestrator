// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/env_config.dart';
import '../models/analytics_model.dart';
import '../models/class_model.dart';
import '../models/class_schedule_model.dart';
import '../models/settings_model.dart';
import '../models/workspace_model.dart';

class CalendarNotConnectedException implements Exception {
  const CalendarNotConnectedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class GoogleAccountNotLinkedException implements Exception {
  const GoogleAccountNotLinkedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DriveNotConnectedException implements Exception {
  const DriveNotConnectedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DriveFileDto {
  const DriveFileDto({
    required this.id,
    required this.name,
    required this.mimeType,
    this.modifiedTime,
  });

  final String id;
  final String name;
  final String mimeType;
  final DateTime? modifiedTime;

  factory DriveFileDto.fromJson(Map<String, dynamic> json) {
    return DriveFileDto(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'Untitled file').toString(),
      mimeType: (json['mimeType'] ?? '').toString(),
      modifiedTime: DateTime.tryParse((json['modifiedTime'] ?? '').toString()),
    );
  }
}

class DriveImportResultDto {
  const DriveImportResultDto({
    required this.message,
    required this.actionsParsed,
    required this.taskCount,
  });

  final String message;
  final int actionsParsed;
  final int taskCount;

  factory DriveImportResultDto.fromJson(Map<String, dynamic> json) {
    final tasks = json['tasks'] as List<dynamic>? ?? const [];
    final rawActionsParsed = json['actionsParsed'] ?? json['actions_parsed'];
    return DriveImportResultDto(
      message: (json['message'] ?? 'Imported Google Drive file.').toString(),
      actionsParsed:
          rawActionsParsed is int
              ? rawActionsParsed
              : int.tryParse('${rawActionsParsed ?? ''}') ?? 0,
      taskCount: tasks.length,
    );
  }
}

class AiChatResponse {
  const AiChatResponse({
    required this.message,
    required this.actionPerformed,
    this.actionType,
  });

  final String message;
  final bool actionPerformed;
  final String? actionType;
}

class FlashcardDto {
  const FlashcardDto({required this.front, required this.back});

  final String front;
  final String back;

  factory FlashcardDto.fromJson(Map<String, dynamic> json) {
    return FlashcardDto(
      front: (json['front'] ?? '').toString(),
      back: (json['back'] ?? '').toString(),
    );
  }
}

class DashboardSummaryDto {
  const DashboardSummaryDto({
    required this.upcomingBlocks,
    required this.pendingTasksCount,
    required this.classesTodayCount,
    this.fixedClasses = const <ClassModel>[],
    this.nextClassName,
    this.nextClassSubtitle,
  });

  final List<DashboardUpcomingBlockDto> upcomingBlocks;
  final int pendingTasksCount;
  final int classesTodayCount;
  final List<ClassModel> fixedClasses;
  final String? nextClassName;
  final String? nextClassSubtitle;

  String get nextClassTitle {
    final nextClass = _nextClassToday(fixedClasses);
    if (nextClass != null) {
      return nextClass.className;
    }

    if (fixedClasses.isNotEmpty) {
      return 'No classes today';
    }

    final normalizedName = nextClassName?.trim() ?? '';
    return normalizedName.isEmpty ? 'No classes today' : normalizedName;
  }

  String get nextClassDetail {
    final nextClass = _nextClassToday(fixedClasses);
    if (nextClass != null) {
      return _formatClassTimeRange(nextClass);
    }

    if (fixedClasses.isNotEmpty) {
      return 'Next Class';
    }

    final normalizedSubtitle = nextClassSubtitle?.trim() ?? '';
    return normalizedSubtitle.isEmpty ? 'Next Class' : normalizedSubtitle;
  }

  int get scheduleClassesTodayCount {
    if (fixedClasses.isEmpty) {
      return classesTodayCount;
    }

    final today = DateTime.now().weekday;
    return fixedClasses
        .where((classItem) => classItem.dayOfWeek == today)
        .length;
  }

  DashboardSummaryDto copyWith({List<ClassModel>? fixedClasses}) {
    return DashboardSummaryDto(
      upcomingBlocks: upcomingBlocks,
      pendingTasksCount: pendingTasksCount,
      classesTodayCount: classesTodayCount,
      fixedClasses: fixedClasses ?? this.fixedClasses,
      nextClassName: nextClassName,
      nextClassSubtitle: nextClassSubtitle,
    );
  }

  factory DashboardSummaryDto.fromJson(Map<String, dynamic> json) {
    final tasks = (json['tasks'] as List<dynamic>?) ?? const [];
    final reminderJobs = (json['reminderJobs'] as List<dynamic>?) ?? const [];
    final blocks =
        ((json['upcoming_blocks'] ?? json['upcomingBlocks'])
            as List<dynamic>?) ??
        reminderJobs;

    return DashboardSummaryDto(
      upcomingBlocks: blocks
          .whereType<Map>()
          .map(
            (block) => DashboardUpcomingBlockDto.fromJson(
              Map<String, dynamic>.from(block),
            ),
          )
          .toList(growable: false),
      pendingTasksCount: _dashboardInt(
        json['pending_tasks_count'] ??
            json['pendingTasksCount'] ??
            json['pending_tasks'] ??
            json['pendingTasks'] ??
            tasks.where(_isDashboardTask).length,
      ),
      classesTodayCount: _dashboardInt(
        json['classes_today_count'] ??
            json['classesTodayCount'] ??
            json['classes_today'] ??
            json['classesToday'] ??
            (((json['next_class_name'] ?? json['nextClassName'])
                        ?.toString()
                        .trim()
                        .isNotEmpty ??
                    false)
                ? 1
                : 0),
      ),
      nextClassName:
          (json['next_class_name'] ?? json['nextClassName'])?.toString(),
      nextClassSubtitle:
          (json['next_class_subtitle'] ?? json['nextClassSubtitle'])
              ?.toString(),
    );
  }
}

ClassModel? _nextClassToday(List<ClassModel> classes) {
  if (classes.isEmpty) {
    return null;
  }

  final now = DateTime.now();
  final todaysUpcomingClasses =
      classes.where((classItem) {
          if (classItem.dayOfWeek != now.weekday) {
            return false;
          }

          final endTime = _classEndToday(classItem, now);
          return endTime != null && !endTime.isBefore(now);
        }).toList()
        ..sort((a, b) {
          final aStart = _classStartToday(a, now);
          final bStart = _classStartToday(b, now);
          if (aStart == null && bStart == null) {
            return 0;
          }
          if (aStart == null) {
            return 1;
          }
          if (bStart == null) {
            return -1;
          }
          return aStart.compareTo(bStart);
        });

  return todaysUpcomingClasses.isEmpty ? null : todaysUpcomingClasses.first;
}

DateTime? _classStartToday(ClassModel classItem, DateTime now) {
  final parts = classItem.startTime.split(':');
  if (parts.length < 2) {
    return null;
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }

  return DateTime(now.year, now.month, now.day, hour, minute);
}

DateTime? _classEndToday(ClassModel classItem, DateTime now) {
  final parts = classItem.endTime.split(':');
  if (parts.length < 2) {
    return null;
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return null;
  }

  return DateTime(now.year, now.month, now.day, hour, minute);
}

String _formatClassTimeRange(ClassModel classItem) {
  return '${_formatClassTime(classItem.startTime)} - ${_formatClassTime(classItem.endTime)}';
}

String _formatClassTime(String rawTime) {
  final parts = rawTime.split(':');
  if (parts.length < 2) {
    return rawTime;
  }

  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) {
    return rawTime;
  }

  final displayHour =
      hour > 12
          ? hour - 12
          : hour == 0
          ? 12
          : hour;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
}

class DashboardUpcomingBlockDto {
  const DashboardUpcomingBlockDto({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.title,
    required this.priority,
  });

  final String id;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String title;
  final String priority;

  factory DashboardUpcomingBlockDto.fromJson(Map<String, dynamic> json) {
    final task = Map<String, dynamic>.from(
      (json['task'] as Map?) ?? const <String, dynamic>{},
    );
    final startsAtRaw =
        json['starts_at'] ?? json['startsAt'] ?? json['reminder_at'];
    final endsAtRaw = json['ends_at'] ?? json['endsAt'];
    final title =
        (task['title'] ?? json['title'] ?? 'Untitled task').toString();
    final id =
        (json['id'] ??
                json['block_id'] ??
                json['blockId'] ??
                task['id'] ??
                startsAtRaw ??
                '')
            .toString();

    return DashboardUpcomingBlockDto(
      id: id.isEmpty ? 'upcoming-${startsAtRaw ?? title}' : id,
      startsAt: DateTime.tryParse('${startsAtRaw ?? ''}'),
      endsAt: DateTime.tryParse('${endsAtRaw ?? ''}'),
      title: title,
      priority:
          (task['priority'] ??
                  task['priority_level'] ??
                  task['priorityLevel'] ??
                  json['priority'] ??
                  'Normal')
              .toString(),
    );
  }
}

class FocusSessionResult {
  const FocusSessionResult({
    required this.streakCount,
    required this.longestStreak,
    this.sessionId,
  });

  final int streakCount;
  final int longestStreak;
  final String? sessionId;

  factory FocusSessionResult.fromJson(Map<String, dynamic> json) {
    final focusSession =
        json['focusSession'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return FocusSessionResult(
      streakCount: _dashboardInt(
        json['streakCount'] ??
            json['streak_count'] ??
            focusSession['streakCount'] ??
            focusSession['streak_count'],
      ),
      longestStreak: _dashboardInt(
        json['longestStreak'] ??
            json['longest_streak'] ??
            focusSession['longestStreak'] ??
            focusSession['longest_streak'],
      ),
      sessionId:
          (focusSession['sessionId'] ?? focusSession['session_id'])?.toString(),
    );
  }
}

int _dashboardInt(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse('${value ?? ''}') ?? 0;
}

bool _isDashboardTask(Object? item) {
  if (item is! Map) {
    return false;
  }

  final task = Map<String, dynamic>.from(item);
  final rawType =
      task['type'] ??
      task['item_type'] ??
      task['itemType'] ??
      task['kind'] ??
      task['entity_type'] ??
      task['entityType'];
  final normalizedType = rawType?.toString().trim().toLowerCase();

  if (normalizedType == null || normalizedType.isEmpty) {
    return true;
  }

  return normalizedType == 'task' ||
      normalizedType == 'primary_task' ||
      normalizedType == 'subtask' ||
      normalizedType == 'sub_task';
}

class ApiService {
  factory ApiService({FlutterSecureStorage? storage}) {
    if (storage != null) {
      return ApiService._internal(storage: storage);
    }

    return instance;
  }

  ApiService._internal({required FlutterSecureStorage storage})
    : _storage = storage {
    debugPrint('Connecting to: $baseUrl');
  }

  static const String _jwtTokenKey = 'jwt_token';
  static const Uuid _uuid = Uuid();
  static final ApiService instance = ApiService._internal(
    storage: const FlutterSecureStorage(),
  );
  static final ValueNotifier<int> taskMutationNotifier = ValueNotifier<int>(0);
  static final ValueNotifier<int> scheduleMutationNotifier = ValueNotifier<int>(
    0,
  );
  static final ValueNotifier<String?> profileNameNotifier =
      ValueNotifier<String?>(null);
  static bool _bypassHealthCheckForTests = false;
  static bool _bypassNetworkForTests = false;
  static String get baseUrl => EnvConfig.apiBaseUrl;

  final FlutterSecureStorage _storage;

  static void notifyTaskMutation() {
    taskMutationNotifier.value++;
  }

  static void notifyScheduleMutation() {
    scheduleMutationNotifier.value++;
  }

  static void notifyProfileNameChanged(String name) {
    final normalizedName = name.trim();
    profileNameNotifier.value = normalizedName.isEmpty ? null : normalizedName;
  }

  @visibleForTesting
  static void enableHealthCheckBypassForTests() {
    _bypassHealthCheckForTests = true;
  }

  @visibleForTesting
  static void enableNetworkBypassForTests() {
    _bypassNetworkForTests = true;
  }

  static bool get _isFlutterTestEnvironment {
    final isTestEnvironment =
        Zone.current[#test.declarer] != null || _bypassNetworkForTests;
    return isTestEnvironment;
  }

  static AnalyticsModel _emptyAnalyticsModel() {
    return const AnalyticsModel(
      streakSnapshot: {'currentStreak': 0, 'longestStreak': 0},
      reminderJobs: <ReminderJobModel>[],
      userBadges: <UserBadgeModel>[],
      notificationPreferences: NotificationPreferencesModel(
        inboxEnabled: true,
        emailEnabled: false,
        reminderLeadMinutes: 30,
        quietHoursStart: '22:00',
        quietHoursEnd: '07:00',
        timeZone: 'UTC',
      ),
    );
  }

  static DashboardSummaryDto _emptyDashboardSummary() {
    return DashboardSummaryDto.fromJson({
      'pendingTasksCount': 0,
      'classesTodayCount': 0,
      'nextClassName': 'No classes today',
    });
  }

  static void _logFetch(String url) {
    print('Attempting to fetch from: $url');
  }

  Map<String, String> _jsonHeaders({String? token}) {
    return {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> login({required String email, required String password}) async {
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final token = response.session?.accessToken;

    if (token == null || token.isEmpty) {
      throw StateError('Login succeeded without access token');
    }

    await _storage.write(key: _jwtTokenKey, value: token);
  }

  Future<bool> isLoggedIn() async {
    final token = await _getValidAccessToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } finally {
      profileNameNotifier.value = null;
      await _storage.delete(key: _jwtTokenKey);
    }
  }

  Future<String?> _getValidAccessToken({bool forceRefresh = false}) async {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;

    if (session == null) {
      await _storage.delete(key: _jwtTokenKey);
      return null;
    }

    final nowInSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresAt = session.expiresAt;
    final shouldRefresh =
        forceRefresh || (expiresAt != null && expiresAt <= nowInSeconds + 30);

    if (!shouldRefresh) {
      await _storage.write(key: _jwtTokenKey, value: session.accessToken);
      return session.accessToken;
    }

    final refreshedToken = await _refreshAccessToken();

    if (refreshedToken != null && refreshedToken.isNotEmpty) {
      await _storage.write(key: _jwtTokenKey, value: refreshedToken);
    }

    return refreshedToken;
  }

  Future<String?> _refreshAccessToken() async {
    final auth = Supabase.instance.client.auth;
    try {
      final refreshedSession = await auth.refreshSession();
      final refreshedToken =
          refreshedSession.session?.accessToken ??
          auth.currentSession?.accessToken;

      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        await _storage.write(key: _jwtTokenKey, value: refreshedToken);
      }

      return refreshedToken;
    } on AuthException {
      await _storage.delete(key: _jwtTokenKey);
      await auth.signOut();
      return null;
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getValidAccessToken();
    return _jsonHeaders(token: token);
  }

  Future<Map<String, String>> authHeaders() => _getHeaders();

  Future<http.Response> checkHealth() async {
    if (_bypassHealthCheckForTests || _isFlutterTestEnvironment) {
      return http.Response('{"status":"ok","source":"test-bypass"}', 200);
    }

    final url = '$baseUrl/health';
    _logFetch(url);
    final response = await http
        .get(Uri.parse(url), headers: _jsonHeaders())
        .timeout(const Duration(seconds: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Health check failed: ${response.statusCode}');
    }

    return response;
  }

  Future<FocusSessionResult> completeFocusSession({
    required int durationMinutes,
    int xp = 0,
  }) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/focus/complete');
    final body = jsonEncode({'durationMinutes': durationMinutes, 'xp': xp});

    var response = await http
        .post(uri, headers: headers, body: body)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(uri, headers: _jsonHeaders(token: refreshedToken), body: body)
          .timeout(const Duration(seconds: 8));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Focus session complete failed: ${response.statusCode} ${response.body}',
      );
    }

    return FocusSessionResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AnalyticsModel> fetchAnalyticsOverview() async {
    if (_isFlutterTestEnvironment) {
      return _emptyAnalyticsModel();
    }

    final headers = await _getHeaders();
    final url = '$baseUrl/analytics/overview';
    _logFetch(url);
    debugPrint('[ApiService] GET $baseUrl/analytics/overview -> request');
    var response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 15));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[ApiService] GET $baseUrl/analytics/overview -> ${response.statusCode}',
      );
      throw Exception(
        'Analytics overview fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    debugPrint(
      '[ApiService] GET $baseUrl/analytics/overview -> ${response.statusCode}',
    );
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return AnalyticsModel.fromJson(decoded);
  }

  Future<DashboardSummaryDto> fetchDashboardSummary() async {
    if (_isFlutterTestEnvironment) {
      return _emptyDashboardSummary();
    }

    final headers = await _getHeaders();
    final url = '$baseUrl/analytics/overview';
    _logFetch(url);
    var response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 15));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Dashboard summary fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return DashboardSummaryDto.fromJson(decoded);
  }

  Future<int> calculateCurrentStreak() async {
    if (_isFlutterTestEnvironment) {
      return 0;
    }

    final headers = await _getHeaders();
    var response = await http
        .get(Uri.parse('$baseUrl/analytics/overview'), headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse('$baseUrl/analytics/overview'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 15));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Streak calculation failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final completionEvents =
        decoded['completionEvents'] as List<dynamic>? ?? const [];
    final completionDates =
        completionEvents
            .whereType<Map<String, dynamic>>()
            .map(_extractCompletionDate)
            .whereType<DateTime>()
            .map(_startOfDay)
            .toSet();

    if (completionDates.isEmpty) {
      final streakSnapshot =
          decoded['streakSnapshot'] as Map<String, dynamic>? ?? const {};
      return _asInt(
        streakSnapshot['currentStreak'] ??
            streakSnapshot['streakCount'] ??
            streakSnapshot['streak_count'],
      );
    }

    final today = _startOfDay(DateTime.now());
    var cursor = today;
    if (!completionDates.contains(cursor)) {
      final yesterday = today.subtract(const Duration(days: 1));
      if (!completionDates.contains(yesterday)) {
        return 0;
      }
      cursor = yesterday;
    }

    var streak = 0;
    while (completionDates.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return streak;
  }

  Future<void> createReminder(
    String taskId,
    String title,
    String reminderAt, {
    String taskType = 'task',
  }) async {
    final headers = await _getHeaders();
    final body = {
      'taskId': taskId,
      'taskType': taskType,
      'title': title,
      'reminderAt': reminderAt,
      'reminder_at': reminderAt,
      'channel': 'inbox',
    };

    var response = await http
        .post(
          Uri.parse('$baseUrl/analytics/reminders'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/analytics/reminders'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Reminder creation failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<void> dismissReminder(String reminderId) async {
    final headers = await _getHeaders();
    const body = {'action': 'read'};

    var response = await http
        .patch(
          Uri.parse('$baseUrl/analytics/reminders/$reminderId'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .patch(
            Uri.parse('$baseUrl/analytics/reminders/$reminderId'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Reminder dismissal failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<SettingsModel> fetchProfileSettings() async {
    if (_isFlutterTestEnvironment) {
      return SettingsModel.fromJson(const <String, dynamic>{});
    }

    final headers = await _getHeaders();
    var response = await http
        .get(Uri.parse('$baseUrl/settings/profile'), headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse('$baseUrl/settings/profile'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Profile fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return SettingsModel.fromJson(decoded);
  }

  Future<void> updateProfileSettings(SettingsModel settings) async {
    final headers = await _getHeaders();
    var response = await http
        .put(
          Uri.parse('$baseUrl/settings/profile'),
          headers: headers,
          body: jsonEncode(settings.toJson()),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .put(
            Uri.parse('$baseUrl/settings/profile'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(settings.toJson()),
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Profile update failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<void> updateProfile(String name) async {
    final headers = await _getHeaders();
    final body = {'name': name};

    var response = await http
        .put(
          Uri.parse('$baseUrl/settings/profile'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .put(
            Uri.parse('$baseUrl/settings/profile'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Profile name update failed: ${response.statusCode} ${response.body}',
      );
    }

    notifyProfileNameChanged(name);
  }

  Future<String?> fetchCurrentProfileName() async {
    if (_isFlutterTestEnvironment) {
      profileNameNotifier.value = null;
      return null;
    }

    final user = Supabase.instance.client.auth.currentUser;
    final userId = user?.id;
    if (userId == null || userId.trim().isEmpty) {
      profileNameNotifier.value = null;
      return null;
    }

    final response =
        await Supabase.instance.client
            .from('user_profiles')
            .select('full_name')
            .eq('id', userId)
            .maybeSingle();
    final fullName = response?['full_name']?.toString().trim();
    final normalizedName =
        fullName == null || fullName.isEmpty ? null : fullName;

    profileNameNotifier.value = normalizedName;
    return normalizedName;
  }

  Future<List<Map<String, dynamic>>> fetchTaskRows() async {
    if (_isFlutterTestEnvironment) {
      return const <Map<String, dynamic>>[];
    }

    final headers = await _getHeaders();
    final url = '$baseUrl/tasks/rows';
    _logFetch(url);
    var response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Task rows fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = decoded['rows'] as List<dynamic>? ?? const [];
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchPrimaryTasks({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (_isFlutterTestEnvironment) {
      return const <Map<String, dynamic>>[];
    }

    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/tasks/primary').replace(
      queryParameters: {
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      },
    );
    final url = uri.toString();
    _logFetch(url);
    var response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Primary task fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final primaryTasks = decoded['primaryTasks'] as List<dynamic>? ?? const [];
    return primaryTasks.whereType<Map<String, dynamic>>().toList(
      growable: false,
    );
  }

  Future<List<Map<String, dynamic>>> getTasks({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (_isFlutterTestEnvironment) {
      return const <Map<String, dynamic>>[];
    }

    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/tasks').replace(
      queryParameters: {
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      },
    );
    final url = uri.toString();
    _logFetch(url);
    var response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Task fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final tasks = decoded['tasks'] as List<dynamic>? ?? const [];
    return tasks.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<Map<String, dynamic>> createTask(
    Map<String, dynamic> taskData, {
    String? status,
    String? taskType,
    String? categoryId,
    String? notes,
  }) async {
    final headers = await _getHeaders();
    final url = '$baseUrl/tasks';
    final payload = _withOptionalTaxonomyFields(
      Map<String, dynamic>.from(taskData),
      status: status,
      taskType: taskType,
      categoryId: categoryId,
      notes: notes,
    );
    var response = await http
        .post(Uri.parse(url), headers: headers, body: jsonEncode(payload))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Task creation failed: ${response.statusCode} ${response.body}',
      );
    }

    notifyTaskMutation();
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['task'] as Map<String, dynamic>? ?? decoded;
  }

  Future<AiChatResponse> sendChatMessage(String message) async {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      throw ArgumentError('Message is required.');
    }

    final headers = await _getHeaders();
    final url = '$baseUrl/ai/chat';
    final body = {'message': trimmedMessage};
    var response = await http
        .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'AI chat failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final aiResponse =
        (decoded['response'] ?? decoded['message'] ?? '').toString().trim();
    if (aiResponse.isEmpty) {
      throw Exception('AI chat returned an empty response.');
    }

    final actionPerformed = decoded['actionPerformed'] == true;
    if (actionPerformed) {
      notifyTaskMutation();
    }

    return AiChatResponse(
      message: aiResponse,
      actionPerformed: actionPerformed,
      actionType: decoded['actionType']?.toString(),
    );
  }

  Future<Map<String, dynamic>> scanImageForTasks({
    required String imageBase64,
    String mimeType = 'image/jpeg',
    String? status,
    String? taskType,
    String? categoryId,
    String? notes,
  }) async {
    final trimmedImage = imageBase64.trim();
    if (trimmedImage.isEmpty) {
      throw ArgumentError('imageBase64 is required.');
    }

    final headers = await _getHeaders();
    final url = '$baseUrl/ai/vision-parse';
    final body = _withOptionalTaxonomyFields(
      {'image_base64': trimmedImage, 'image_mime_type': mimeType},
      status: status,
      taskType: taskType,
      categoryId: categoryId,
      notes: notes,
    );
    final uri = Uri.parse(url);
    final encodedBody = jsonEncode(body);

    Future<http.Response> postVision(Map<String, String> requestHeaders) {
      return http
          .post(uri, headers: requestHeaders, body: encodedBody)
          .timeout(const Duration(seconds: 60));
    }

    var response = await postVision(headers);

    if (response.statusCode == 401) {
      final refreshedToken = await _refreshAccessToken();
      if (refreshedToken == null || refreshedToken.isEmpty) {
        throw Exception(
          'Vision scan failed: token refresh did not return a session.',
        );
      }

      response = await postVision(_jsonHeaders(token: refreshedToken));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Vision scan failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded;
  }

  Future<List<FlashcardDto>> generateFlashcardsFromImage({
    required String imageBase64,
    String mimeType = 'image/jpeg',
  }) async {
    final trimmedImage = imageBase64.trim();
    if (trimmedImage.isEmpty) {
      throw ArgumentError('imageBase64 is required.');
    }

    final headers = await _getHeaders();
    final url = '$baseUrl/ai/vision-flashcards';
    final body = jsonEncode({
      'image_base64': trimmedImage,
      'image_mime_type': mimeType,
    });
    final uri = Uri.parse(url);

    Future<http.Response> postFlashcards(Map<String, String> requestHeaders) {
      return http
          .post(uri, headers: requestHeaders, body: body)
          .timeout(const Duration(seconds: 60));
    }

    var response = await postFlashcards(headers);

    if (response.statusCode == 401) {
      final refreshedToken = await _refreshAccessToken();
      if (refreshedToken == null || refreshedToken.isEmpty) {
        throw Exception(
          'Flashcard generation failed: token refresh did not return a session.',
        );
      }

      response = await postFlashcards(_jsonHeaders(token: refreshedToken));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Flashcard generation failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final flashcardsJson = decoded['flashcards'] as List<dynamic>? ?? const [];
    return flashcardsJson
        .whereType<Map<String, dynamic>>()
        .map(FlashcardDto.fromJson)
        .toList(growable: false);
  }

  Map<String, dynamic> _withOptionalTaxonomyFields(
    Map<String, dynamic> payload, {
    String? status,
    String? taskType,
    String? categoryId,
    String? notes,
  }) {
    void setIfNotBlank(String key, String? value) {
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        payload[key] = normalized;
      }
    }

    setIfNotBlank('status', status);
    setIfNotBlank('task_type', taskType);
    setIfNotBlank('category_id', categoryId);
    setIfNotBlank('notes', notes);
    return payload;
  }

  Future<void> updateSubTaskCompletion({
    required String id,
    required bool completed,
  }) async {
    final headers = await _getHeaders();
    var response = await http
        .patch(
          Uri.parse('$baseUrl/tasks/subtasks/$id'),
          headers: headers,
          body: jsonEncode({'completed': completed}),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .patch(
            Uri.parse('$baseUrl/tasks/subtasks/$id'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode({'completed': completed}),
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Subtask update failed: ${response.statusCode} ${response.body}',
      );
    }

    notifyTaskMutation();
  }

  Future<void> deleteAllTasks() async {
    if (_isFlutterTestEnvironment) {
      notifyTaskMutation();
      return;
    }

    final headers = await _getHeaders();
    debugPrint('[ApiService] DELETE $baseUrl/tasks -> request');

    var response = await http
        .delete(Uri.parse('$baseUrl/tasks'), headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .delete(
            Uri.parse('$baseUrl/tasks'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[ApiService] DELETE $baseUrl/tasks -> ${response.statusCode}',
      );
      throw Exception(
        'Task deletion failed: ${response.statusCode} ${response.body}',
      );
    }

    debugPrint('[ApiService] DELETE $baseUrl/tasks -> ${response.statusCode}');
    notifyTaskMutation();
  }

  Future<void> deleteTask(String id) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/tasks/$id');

    var response = await http
        .delete(uri, headers: headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .delete(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 8));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Task delete failed: ${response.statusCode} ${response.body}',
      );
    }

    notifyTaskMutation();
  }

  Future<List<dynamic>> orchestrateGoal(String goal) async {
    final headers = await _getHeaders();
    final body = {'goal': goal};

    var response = await http
        .post(
          Uri.parse('$baseUrl/ai/orchestrate'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/ai/orchestrate'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'AI orchestration failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic>) {
      throw Exception('AI orchestration did not return a JSON array.');
    }

    return decoded;
  }

  Future<void> saveOrchestratedTasks({
    required String goal,
    required List<dynamic> tasks,
  }) async {
    final headers = await _getHeaders();
    final runId = _uuid.v4();
    final body = {'runId': runId, 'courseTitle': goal, 'tasks': tasks};

    var response = await http
        .post(
          Uri.parse('$baseUrl/tasks/save-run'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/tasks/save-run'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Saving orchestrated tasks failed: ${response.statusCode} ${response.body}',
      );
    }

    notifyTaskMutation();
  }

  Future<Map<String, dynamic>> createOrchestrationRun(String goal) async {
    final headers = await _getHeaders();
    final body = {
      'kind': 'assignment_breakdown',
      'clientKey': 'mobile-${DateTime.now().millisecondsSinceEpoch}',
      'payload': {'text': goal},
      'sourceSurface': 'mobile',
    };

    var response = await http
        .post(
          Uri.parse('$baseUrl/orchestration/runs'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/orchestration/runs'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return {
      'statusCode': response.statusCode,
      'body': decoded,
      'runId': (decoded['run'] as Map<String, dynamic>?)?['id']?.toString(),
    };
  }

  Future<List<ClassModel>> fetchFixedClasses() async {
    if (_isFlutterTestEnvironment) {
      return const <ClassModel>[];
    }

    final headers = await _getHeaders();
    final url = '$baseUrl/calendar/fixed-classes';
    _logFetch(url);
    var response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Fixed classes fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final classes = decoded['classes'] as List<dynamic>? ?? const [];
    return classes
        .whereType<Map<String, dynamic>>()
        .map(ClassModel.fromJson)
        .toList(growable: false);
  }

  Future<List<ClassSchedule>> fetchClassSchedules() async {
    if (_isFlutterTestEnvironment) {
      return const <ClassSchedule>[];
    }

    final headers = await _getHeaders();
    final url = '$baseUrl/calendar/fixed-classes';
    _logFetch(url);
    var response = await http
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Class schedule fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final classes = decoded['classes'] as List<dynamic>? ?? const [];
    return classes
        .whereType<Map<String, dynamic>>()
        .map(ClassSchedule.fromJson)
        .toList(growable: false);
  }

  Future<bool> fetchCalendarStatus() async {
    if (_isFlutterTestEnvironment) {
      return false;
    }

    final headers = await _getHeaders();
    var response = await http
        .get(Uri.parse('$baseUrl/calendar/status'), headers: headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse('$baseUrl/calendar/status'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 8));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Calendar status fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    print('[ApiService] Calendar status JSON received: $decoded');
    return decoded['connected'] == true;
  }

  Future<String> getCalendarConnectUrl() async {
    final headers = await _getHeaders();
    final connectHeaders = {...headers, 'ngrok-skip-browser-warning': 'true'};
    debugPrint('[ApiService] POST $baseUrl/calendar/connect-url -> request');

    var response = await http
        .post(
          Uri.parse('$baseUrl/calendar/connect-url'),
          headers: connectHeaders,
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/calendar/connect-url'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 8));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[ApiService] POST $baseUrl/calendar/connect-url -> ${response.statusCode}',
      );
      throw Exception(
        'Calendar connect URL failed: ${response.statusCode} ${response.body}',
      );
    }

    debugPrint(
      '[ApiService] POST $baseUrl/calendar/connect-url -> ${response.statusCode}',
    );

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final url = (decoded['url'] ?? '').toString();
    if (url.isEmpty) {
      throw Exception('Calendar connect URL response was missing a url field.');
    }

    return url;
  }

  Future<void> syncCalendar() async {
    if (_isFlutterTestEnvironment) {
      return;
    }

    final headers = await _getHeaders();
    debugPrint('[ApiService] POST $baseUrl/calendar/sync -> request');

    var response = await http
        .post(Uri.parse('$baseUrl/calendar/sync'), headers: headers)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/calendar/sync'),
            headers: _jsonHeaders(token: refreshedToken),
          )
          .timeout(const Duration(seconds: 30));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[ApiService] POST $baseUrl/calendar/sync -> ${response.statusCode}',
      );

      if (response.statusCode == 401) {
        throw const GoogleAccountNotLinkedException(
          'Your session expired. Please sign in again.',
        );
      }

      if (response.statusCode == 400) {
        final decoded =
            jsonDecode(response.body) as Map<String, dynamic>? ?? const {};
        if (decoded['error'] == 'NOT_CONNECTED') {
          throw CalendarNotConnectedException(
            (decoded['message'] ?? 'Connect Google Calendar first.').toString(),
          );
        }
      }

      throw Exception(
        'Calendar sync failed: ${response.statusCode} ${response.body}',
      );
    }

    debugPrint(
      '[ApiService] POST $baseUrl/calendar/sync -> ${response.statusCode}',
    );
  }

  Future<void> syncTasksToCalendar() async {
    await syncCalendar();
  }

  Future<void> rebuildCalendarSchedule(String userId) async {
    if (_isFlutterTestEnvironment) {
      return;
    }

    final token = await _getValidAccessToken();
    final headers = _jsonHeaders(token: token);
    debugPrint(
      '[ApiService] POST $baseUrl/calendar/rebuild -> request for user $userId',
    );

    var response = await http
        .post(Uri.parse('$baseUrl/calendar/rebuild'), headers: headers)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/calendar/rebuild'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 30));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[ApiService] POST $baseUrl/calendar/rebuild -> ${response.statusCode}',
      );
      throw Exception(
        'Calendar rebuild failed: ${response.statusCode} ${response.body}',
      );
    }

    debugPrint(
      '[ApiService] POST $baseUrl/calendar/rebuild -> ${response.statusCode}',
    );
  }

  Future<bool> fetchDriveStatus() async {
    if (_isFlutterTestEnvironment) {
      return false;
    }

    final headers = await _getHeaders();
    var response = await http
        .get(Uri.parse('$baseUrl/drive/status'), headers: headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse('$baseUrl/drive/status'),
            headers: _jsonHeaders(token: refreshedToken),
          )
          .timeout(const Duration(seconds: 8));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Drive status fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return decoded['connected'] == true;
  }

  Future<String> getDriveConnectUrl() async {
    final headers = await _getHeaders();
    var response = await http
        .post(Uri.parse('$baseUrl/drive/connect-url'), headers: headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/drive/connect-url'),
            headers: _jsonHeaders(token: refreshedToken),
          )
          .timeout(const Duration(seconds: 8));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Drive connect URL failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final url = (decoded['url'] ?? '').toString();
    if (url.isEmpty) {
      throw Exception('Drive connect URL response was missing a url field.');
    }

    return url;
  }

  Future<List<DriveFileDto>> listDriveFiles({String query = ''}) async {
    if (_isFlutterTestEnvironment) {
      return const <DriveFileDto>[];
    }

    final uri = Uri.parse('$baseUrl/drive/files').replace(
      queryParameters: query.trim().isEmpty ? null : {'q': query.trim()},
    );
    final headers = await _getHeaders();
    var response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(uri, headers: _jsonHeaders(token: refreshedToken))
          .timeout(const Duration(seconds: 15));
    }

    if (response.statusCode == 400) {
      throw const DriveNotConnectedException('Connect Google Drive first.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Drive files fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final files = decoded['files'] as List<dynamic>? ?? const [];
    return files
        .whereType<Map>()
        .map((file) => DriveFileDto.fromJson(Map<String, dynamic>.from(file)))
        .where((file) => file.id.isNotEmpty)
        .toList(growable: false);
  }

  Future<DriveImportResultDto> importDriveFile(String fileId) async {
    final normalizedFileId = fileId.trim();
    if (normalizedFileId.isEmpty) {
      throw ArgumentError('fileId is required.');
    }

    final body = jsonEncode({'fileId': normalizedFileId});
    final headers = await _getHeaders();
    var response = await http
        .post(Uri.parse('$baseUrl/drive/import'), headers: headers, body: body)
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/drive/import'),
            headers: _jsonHeaders(token: refreshedToken),
            body: body,
          )
          .timeout(const Duration(seconds: 60));
    }

    if (response.statusCode == 400) {
      throw const DriveNotConnectedException('Connect Google Drive first.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Drive import failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    notifyTaskMutation();
    return DriveImportResultDto.fromJson(decoded);
  }

  Future<void> saveFixedClass(ClassModel newClass) async {
    final headers = await _getHeaders();
    final body = {
      'classes': [newClass.toJson()],
    };

    var response = await http
        .post(
          Uri.parse('$baseUrl/calendar/fixed-classes/bulk'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/calendar/fixed-classes/bulk'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Fixed class save failed: ${response.statusCode} ${response.body}',
      );
    }

    notifyScheduleMutation();
  }

  Future<void> deleteClass(String classId) async {
    final normalizedClassId = classId.trim();
    if (normalizedClassId.isEmpty) {
      throw ArgumentError('classId is required.');
    }

    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/calendar/fixed-classes/$normalizedClassId');

    var response = await http
        .delete(uri, headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .delete(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Fixed class delete failed: ${response.statusCode} ${response.body}',
      );
    }

    notifyScheduleMutation();
  }

  Future<List<WorkspaceModel>> fetchWorkspacesOverview() async {
    if (_isFlutterTestEnvironment) {
      return const <WorkspaceModel>[];
    }

    final headers = await _getHeaders();
    var response = await http
        .get(Uri.parse('$baseUrl/workspaces/overview'), headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse('$baseUrl/workspaces/overview'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Workspace overview fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final workspaces = decoded['workspaces'] as List<dynamic>? ?? const [];
    return workspaces
        .whereType<Map<String, dynamic>>()
        .map(WorkspaceModel.fromJson)
        .toList(growable: false);
  }

  Future<void> createWorkspace(String name, String description) async {
    final headers = await _getHeaders();
    final body = {'name': name, 'description': description};

    var response = await http
        .post(
          Uri.parse('$baseUrl/workspaces'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/workspaces'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Workspace creation failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<void> joinWorkspace(String inviteCode) async {
    final headers = await _getHeaders();
    final body = {'inviteCode': inviteCode};

    var response = await http
        .post(
          Uri.parse('$baseUrl/workspaces/join'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .post(
            Uri.parse('$baseUrl/workspaces/join'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Workspace join failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<String> getWorkspaceShareLink(String id) async {
    final headers = await _getHeaders();

    var response = await http
        .get(Uri.parse('$baseUrl/workspaces/$id/share'), headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse('$baseUrl/workspaces/$id/share'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
          )
          .timeout(const Duration(seconds: 5));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Workspace share fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['inviteCode'] ?? '').toString();
  }

  static DateTime? _extractCompletionDate(Map<String, dynamic> json) {
    final rawValue =
        json['completed_at'] ??
        json['completedAt'] ??
        json['created_at'] ??
        json['createdAt'] ??
        json['date'];
    if (rawValue == null) {
      return null;
    }

    return DateTime.tryParse(rawValue.toString())?.toLocal();
  }

  static DateTime _startOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
