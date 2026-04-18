class ProfileSettings {
  const ProfileSettings({
    this.wakeTime,
    this.sleepTime,
    this.breakfastStart,
    this.breakfastEnd,
    this.lunchStart,
    this.lunchEnd,
    this.dinnerStart,
    this.dinnerEnd,
    this.transitBufferMinutes,
  });

  final String? wakeTime;
  final String? sleepTime;
  final String? breakfastStart;
  final String? breakfastEnd;
  final String? lunchStart;
  final String? lunchEnd;
  final String? dinnerStart;
  final String? dinnerEnd;
  final int? transitBufferMinutes;

  factory ProfileSettings.fromJson(Map<String, dynamic> json) {
    return ProfileSettings(
      wakeTime: _asNullableString(json['wakeTime']),
      sleepTime: _asNullableString(json['sleepTime']),
      breakfastStart: _asNullableString(json['breakfastStart']),
      breakfastEnd: _asNullableString(json['breakfastEnd']),
      lunchStart: _asNullableString(json['lunchStart']),
      lunchEnd: _asNullableString(json['lunchEnd']),
      dinnerStart: _asNullableString(json['dinnerStart']),
      dinnerEnd: _asNullableString(json['dinnerEnd']),
      transitBufferMinutes: _asNullableInt(json['transitBufferMinutes']),
    );
  }

  String get wakeSleepLabel {
    if (wakeTime == null && sleepTime == null) {
      return 'No wake/sleep settings yet';
    }

    return '${wakeTime ?? '--:--'} to ${sleepTime ?? '--:--'}';
  }

  String get mealsLabel {
    final segments = <String>[
      _rangeLabel('Breakfast', breakfastStart, breakfastEnd),
      _rangeLabel('Lunch', lunchStart, lunchEnd),
      _rangeLabel('Dinner', dinnerStart, dinnerEnd),
    ]..removeWhere((value) => value.isEmpty);

    if (segments.isEmpty) {
      return 'No meal windows saved';
    }

    return segments.join(' | ');
  }

  static String _rangeLabel(String label, String? start, String? end) {
    if (start == null || end == null) {
      return '';
    }

    return '$label $start-$end';
  }

  static String? _asNullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final stringValue = value.toString().trim();
    return stringValue.isEmpty ? null : stringValue;
  }

  static int? _asNullableInt(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(value.toString());
  }
}
