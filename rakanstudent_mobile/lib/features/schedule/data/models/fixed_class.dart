class FixedClass {
  const FixedClass({
    required this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.className,
    this.classType,
    this.location,
    this.lecturer,
  });

  final String id;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String className;
  final String? classType;
  final String? location;
  final String? lecturer;

  factory FixedClass.fromJson(Map<String, dynamic> json) {
    return FixedClass(
      id: (json['id'] ?? '').toString(),
      dayOfWeek: _asInt(json['day_of_week']),
      startTime: (json['start_time'] ?? '').toString(),
      endTime: (json['end_time'] ?? '').toString(),
      className: (json['class_name'] ?? 'Untitled class').toString(),
      classType: _asNullableString(json['class_type']),
      location: _asNullableString(json['location']),
      lecturer: _asNullableString(json['lecturer']),
    );
  }

  String get dayLabel {
    const dayNames = <int, String>{
      0: 'Sun',
      1: 'Mon',
      2: 'Tue',
      3: 'Wed',
      4: 'Thu',
      5: 'Fri',
      6: 'Sat',
    };

    return dayNames[dayOfWeek] ?? 'Day $dayOfWeek';
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String? _asNullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final stringValue = value.toString().trim();
    return stringValue.isEmpty ? null : stringValue;
  }
}
