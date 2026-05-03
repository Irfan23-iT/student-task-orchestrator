// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/analytics_model.dart';
import '../models/class_model.dart';
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

class ApiService {
  ApiService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage() {
    debugPrint('Connecting to: $baseUrl');
  }

  static const String _jwtTokenKey = 'jwt_token';
  static const Uuid _uuid = Uuid();
  static final ValueNotifier<int> taskMutationNotifier = ValueNotifier<int>(0);
  static const String baseUrl = 'http://192.168.0.129:5000/api';

  final FlutterSecureStorage _storage;

  static void _emitTaskMutation() {
    taskMutationNotifier.value++;
  }

  static void _logFetch(String url) {
    print('Attempting to fetch from: $url');
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
    final token = await _storage.read(key: _jwtTokenKey);
    return token != null;
  }

  Future<void> logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } finally {
      await _storage.delete(key: _jwtTokenKey);
    }
  }

  Future<String?> _getValidAccessToken({bool forceRefresh = false}) async {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;

    if (session == null) {
      return _storage.read(key: _jwtTokenKey);
    }

    final nowInSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expiresAt = session.expiresAt;
    final shouldRefresh =
        forceRefresh || (expiresAt != null && expiresAt <= nowInSeconds + 30);

    if (!shouldRefresh) {
      await _storage.write(key: _jwtTokenKey, value: session.accessToken);
      return session.accessToken;
    }

    final refreshedSession = await auth.refreshSession();
    final refreshedToken =
        refreshedSession.session?.accessToken ??
        auth.currentSession?.accessToken;

    if (refreshedToken != null && refreshedToken.isNotEmpty) {
      await _storage.write(key: _jwtTokenKey, value: refreshedToken);
    }

    return refreshedToken;
  }

  Future<Map<String, String>> _getHeaders() async {
    final session = Supabase.instance.client.auth.currentSession;
    final token = session?.accessToken ?? await _getValidAccessToken();

    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> checkHealth() async {
    const url = '$baseUrl/health';
    _logFetch(url);
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Health check failed: ${response.statusCode}');
    }

    return response;
  }

  Future<AnalyticsModel> fetchAnalyticsOverview() async {
    final headers = await _getHeaders();
    const url = '$baseUrl/analytics/overview';
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

  Future<int> calculateCurrentStreak() async {
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
    String subTaskId,
    String title,
    String reminderAt,
  ) async {
    final headers = await _getHeaders();
    final body = {
      'subTaskId': subTaskId,
      'title': title,
      'reminderAt': reminderAt,
      'channel': 'email',
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
  }

  Future<List<Map<String, dynamic>>> fetchTaskRows() async {
    final headers = await _getHeaders();
    const url = '$baseUrl/tasks/rows';
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

    _emitTaskMutation();
  }

  Future<void> deleteAllTasks() async {
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
    _emitTaskMutation();
  }

  Future<void> deleteTask(String id) async {
    final headers = await _getHeaders();
    final body = {
      'subTaskIds': [id],
    };

    var response = await http
        .delete(
          Uri.parse('$baseUrl/tasks/session'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .delete(
            Uri.parse('$baseUrl/tasks/session'),
            headers: {
              'Content-Type': 'application/json',
              if (refreshedToken != null)
                'Authorization': 'Bearer $refreshedToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Task delete failed: ${response.statusCode} ${response.body}',
      );
    }

    _emitTaskMutation();
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

    _emitTaskMutation();
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
    final headers = await _getHeaders();
    const url = '$baseUrl/calendar/fixed-classes';
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

  Future<bool> fetchCalendarStatus() async {
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
    final headers = await _getHeaders();
    debugPrint('[ApiService] POST $baseUrl/calendar/sync -> request');

    var response = await http
        .post(Uri.parse('$baseUrl/calendar/sync'), headers: headers)
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 401) {
      throw const GoogleAccountNotLinkedException(
        'Google Account not linked. Please link on Web App.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[ApiService] POST $baseUrl/calendar/sync -> ${response.statusCode}',
      );

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
  }

  Future<List<WorkspaceModel>> fetchWorkspacesOverview() async {
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
