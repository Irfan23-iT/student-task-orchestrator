import 'dart:convert';

import 'app_error.dart';

class BackendErrorParser {
  const BackendErrorParser._();

  static AppError fromResponse({
    required int statusCode,
    required String body,
    String? requestId,
  }) {
    String message = 'Request failed';
    String? details;

    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          message =
              (decoded['error'] as String?)?.trim().isNotEmpty == true
                  ? decoded['error'] as String
                  : message;
          details = (decoded['details'] as String?)?.trim();
        }
      } catch (_) {
        details = body;
      }
    }

    return AppError(
      message: message,
      details: details,
      statusCode: statusCode,
      requestId: requestId,
    );
  }

  static AppError fromException(Object error, {StackTrace? stackTrace}) {
    if (error is AppError) {
      return error;
    }

    return AppError(message: 'Unexpected error', details: error.toString());
  }
}
