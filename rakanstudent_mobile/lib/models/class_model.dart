class ClassModel {
  const ClassModel({
    required this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.className,
    required this.classType,
    this.location,
    this.lecturer,
  });

  final String? id;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String className;
  final String classType;
  final String? location;
  final String? lecturer;

  factory ClassModel.fromJson(Map<String, dynamic> json) {
    return ClassModel(
      id: json['id']?.toString(),
      dayOfWeek: _asDayOfWeek(json['day_of_week'] ?? json['dayOfWeek']),
      startTime: (json['start_time'] ?? json['startTime'] ?? '').toString(),
      endTime: (json['end_time'] ?? json['endTime'] ?? '').toString(),
      className: (json['class_name'] ?? json['className'] ?? '').toString(),
      classType: (json['class_type'] ?? json['classType'] ?? '').toString(),
      location: _asNullableString(json['location']),
      lecturer: _asNullableString(json['lecturer']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'day_of_week': _mapIntToDayString(dayOfWeek),
      'start_time': startTime,
      'end_time': endTime,
      'class_name': className,
      'class_type': classType,
      if (location != null && location!.isNotEmpty) 'location': location,
      if (lecturer != null && lecturer!.isNotEmpty) 'lecturer': lecturer,
    };
  }

  static String? _asNullableString(Object? value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  static int _asDayOfWeek(Object? value) {
    if (value is int) {
      return value;
    }

    final normalized = '${value ?? ''}'.trim().toUpperCase();
    const dayMap = <String, int>{
      'MON': 1,
      'TUE': 2,
      'WED': 3,
      'THU': 4,
      'FRI': 5,
      'SAT': 6,
      'SUN': 7,
    };

    if (dayMap.containsKey(normalized)) {
      return dayMap[normalized]!;
    }

    return int.tryParse(normalized) ?? 0;
  }

  static String _mapIntToDayString(int day) {
    const dayMap = <int, String>{
      1: 'MON',
      2: 'TUE',
      3: 'WED',
      4: 'THU',
      5: 'FRI',
      6: 'SAT',
      7: 'SUN',
    };

    return dayMap[day] ?? 'MON';
  }
}
