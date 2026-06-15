class ClassSchedule {
  const ClassSchedule({
    required this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    String? courseName,
    String? className,
    required this.colorHex,
    this.classType,
    this.location,
    this.lecturer,
  }) : courseName = courseName ?? className ?? 'Untitled class';

  final String id;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String courseName;
  final String colorHex;
  final String? classType;
  final String? location;
  final String? lecturer;

  String get className => courseName;

  factory ClassSchedule.fromJson(Map<String, dynamic> json) {
    return ClassSchedule(
      id: (json['id'] ?? '').toString(),
      dayOfWeek: _asDayOfWeek(json['day_of_week'] ?? json['dayOfWeek']),
      startTime: (json['start_time'] ?? json['startTime'] ?? '').toString(),
      endTime: (json['end_time'] ?? json['endTime'] ?? '').toString(),
      courseName:
          (json['course_name'] ??
                  json['courseName'] ??
                  json['class_name'] ??
                  json['className'] ??
                  'Untitled class')
              .toString(),
      classType: _asNullableString(json['class_type'] ?? json['classType']),
      colorHex: _normalizeColorHex(json['color_hex'] ?? json['colorHex']),
      location: _asNullableString(json['location']),
      lecturer: _asNullableString(json['lecturer']),
    );
  }

  static int _asDayOfWeek(Object? value) {
    if (value is int) {
      if (value == 0) return 7;
      return value;
    }

    final normalized = '${value ?? ''}'.trim().toUpperCase();
    const dayMap = <String, int>{
      'MON': 1,
      'MONDAY': 1,
      'TUE': 2,
      'TUESDAY': 2,
      'WED': 3,
      'WEDNESDAY': 3,
      'THU': 4,
      'THURSDAY': 4,
      'FRI': 5,
      'FRIDAY': 5,
      'SAT': 6,
      'SATURDAY': 6,
      'SUN': 7,
      'SUNDAY': 7,
    };

    if (dayMap.containsKey(normalized)) {
      return dayMap[normalized]!;
    }

    final parsed = int.tryParse(normalized) ?? 0;
    if (parsed == 0) return 7;
    return parsed;
  }

  static String _normalizeColorHex(Object? value) {
    final normalized = value?.toString().trim();
    if (normalized == null || normalized.isEmpty) {
      return '#2563EB';
    }

    final withHash = normalized.startsWith('#') ? normalized : '#$normalized';
    if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(withHash)) {
      return withHash.toUpperCase();
    }

    return '#2563EB';
  }

  static String? _asNullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }
}
