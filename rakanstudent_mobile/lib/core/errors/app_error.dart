class AppError implements Exception {
  const AppError({
    required this.message,
    this.details,
    this.statusCode,
    this.requestId,
  });

  final String message;
  final String? details;
  final int? statusCode;
  final String? requestId;

  String get userMessage =>
      details?.trim().isNotEmpty == true ? details! : message;

  @override
  String toString() => userMessage;
}
