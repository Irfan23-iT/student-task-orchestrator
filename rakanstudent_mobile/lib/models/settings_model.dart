class SettingsModel {
  const SettingsModel({
    required this.wakeTime,
    required this.sleepTime,
    required this.breakfastStart,
    required this.breakfastEnd,
    required this.lunchStart,
    required this.lunchEnd,
    required this.dinnerStart,
    required this.dinnerEnd,
    required this.transitBufferMinutes,
  });

  final String wakeTime;
  final String sleepTime;
  final String breakfastStart;
  final String breakfastEnd;
  final String lunchStart;
  final String lunchEnd;
  final String dinnerStart;
  final String dinnerEnd;
  final int transitBufferMinutes;

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    final rawSettings =
        json['settings'] is Map<String, dynamic>
            ? json['settings'] as Map<String, dynamic>
            : json;

    return SettingsModel(
      wakeTime: (rawSettings['wakeTime'] ?? '').toString(),
      sleepTime: (rawSettings['sleepTime'] ?? '').toString(),
      breakfastStart: (rawSettings['breakfastStart'] ?? '').toString(),
      breakfastEnd: (rawSettings['breakfastEnd'] ?? '').toString(),
      lunchStart: (rawSettings['lunchStart'] ?? '').toString(),
      lunchEnd: (rawSettings['lunchEnd'] ?? '').toString(),
      dinnerStart: (rawSettings['dinnerStart'] ?? '').toString(),
      dinnerEnd: (rawSettings['dinnerEnd'] ?? '').toString(),
      transitBufferMinutes: _asInt(rawSettings['transitBufferMinutes']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'wakeTime': wakeTime,
      'sleepTime': sleepTime,
      'breakfastStart': breakfastStart,
      'breakfastEnd': breakfastEnd,
      'lunchStart': lunchStart,
      'lunchEnd': lunchEnd,
      'dinnerStart': dinnerStart,
      'dinnerEnd': dinnerEnd,
      'transitBufferMinutes': transitBufferMinutes,
    };
  }

  SettingsModel copyWith({
    String? wakeTime,
    String? sleepTime,
    String? breakfastStart,
    String? breakfastEnd,
    String? lunchStart,
    String? lunchEnd,
    String? dinnerStart,
    String? dinnerEnd,
    int? transitBufferMinutes,
  }) {
    return SettingsModel(
      wakeTime: wakeTime ?? this.wakeTime,
      sleepTime: sleepTime ?? this.sleepTime,
      breakfastStart: breakfastStart ?? this.breakfastStart,
      breakfastEnd: breakfastEnd ?? this.breakfastEnd,
      lunchStart: lunchStart ?? this.lunchStart,
      lunchEnd: lunchEnd ?? this.lunchEnd,
      dinnerStart: dinnerStart ?? this.dinnerStart,
      dinnerEnd: dinnerEnd ?? this.dinnerEnd,
      transitBufferMinutes: transitBufferMinutes ?? this.transitBufferMinutes,
    );
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
