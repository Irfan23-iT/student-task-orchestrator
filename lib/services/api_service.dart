import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/analytics_model.dart';
import '../models/class_model.dart';
import '../models/settings_model.dart';
import '../models/workspace_model.dart';

class ApiService {
  ApiService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _jwtTokenKey = 'jwt_token';

  final FlutterSecureStorage _storage;
  final String baseUrl = dotenv.env['API_URL'] ?? '';

  Future<void> login({
    required String email,
    required String password,
  }) async {
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
        refreshedSession.session?.accessToken ?? auth.currentSession?.accessToken;

    if (refreshedToken != null && refreshedToken.isNotEmpty) {
      await _storage.write(key: _jwtTokenKey, value: refreshedToken);
    }

    return refreshedToken;
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getValidAccessToken();

    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> checkHealth() async {
    final response = await http
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Health check failed: ${response.statusCode}');
    }

    return response;
  }

  Future<AnalyticsModel> fetchAnalyticsOverview() async {
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
        'Analytics overview fetch failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return AnalyticsModel.fromJson(decoded);
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

  Future<List<Map<String, dynamic>>> fetchTaskRows() async {
    final headers = await _getHeaders();
    var response = await http
        .get(Uri.parse('$baseUrl/tasks/rows'), headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse('$baseUrl/tasks/rows'),
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
    var response = await http
        .get(Uri.parse('$baseUrl/calendar/fixed-classes'), headers: headers)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 401) {
      final refreshedToken = await _getValidAccessToken(forceRefresh: true);
      response = await http
          .get(
            Uri.parse('$baseUrl/calendar/fixed-classes'),
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
}
