import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_config.dart';
import '../errors/app_error.dart';
import '../errors/backend_error_parser.dart';

class ApiClient {
  ApiClient({http.Client? httpClient, SupabaseClient? supabaseClient})
    : _httpClient = httpClient ?? http.Client(),
      _supabaseClient = supabaseClient ?? Supabase.instance.client;

  final http.Client _httpClient;
  final SupabaseClient _supabaseClient;

  Future<ApiResponse> get(String path) {
    return _sendRequest('GET', path);
  }

  Future<ApiResponse> post(String path, {Object? body}) {
    return _sendRequest('POST', path, body: body);
  }

  Future<ApiResponse> put(String path, {Object? body}) {
    return _sendRequest('PUT', path, body: body);
  }

  Future<ApiResponse> patch(String path, {Object? body}) {
    return _sendRequest('PATCH', path, body: body);
  }

  Future<ApiResponse> delete(String path, {Object? body}) {
    return _sendRequest('DELETE', path, body: body);
  }

  Future<ApiResponse> _sendRequest(
    String method,
    String path, {
    Object? body,
    bool hasRetried = false,
  }) async {
    final session = _supabaseClient.auth.currentSession;
    final token = session?.accessToken;

    final uri = Uri.parse('${EnvConfig.apiBaseUrl}$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    late final http.Response response;

    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      case 'PUT':
        response = await _httpClient.put(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      case 'DELETE':
        response = await _httpClient.delete(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      default:
        throw AppError(message: 'Unsupported HTTP method', details: method);
    }

    final requestId = response.headers['x-request-id'];
    if (response.statusCode == 401 && !hasRetried) {
      final refreshed = await _supabaseClient.auth.refreshSession();
      if (refreshed.session == null) {
        await _supabaseClient.auth.signOut();
        throw const AppError(
          message: 'Unauthorized',
          details: 'Please sign in again.',
        );
      }

      return _sendRequest(method, path, body: body, hasRetried: true);
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendErrorParser.fromResponse(
        statusCode: response.statusCode,
        body: response.body,
        requestId: requestId,
      );
    }

    return ApiResponse(
      statusCode: response.statusCode,
      body: response.body,
      requestId: requestId,
    );
  }
}

class ApiResponse {
  const ApiResponse({
    required this.statusCode,
    required this.body,
    this.requestId,
  });

  final int statusCode;
  final String body;
  final String? requestId;

  dynamic decodeJson() {
    if (body.isEmpty) {
      return null;
    }

    return jsonDecode(body);
  }
}
