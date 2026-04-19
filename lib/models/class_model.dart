class ClassModel {
  const ClassModel({
    required this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.className,
    required this.classType,
  });

  final String? id;
  final int dayOfWeek;
  final String startTime;
  final String endTime;
  final String className;
  final String classType;

  factory ClassModel.fromJson(Map<String, dynamic> json) {
    return ClassModel(
      id: json['id']?.toString(),
      dayOfWeek: _asInt(json['day_of_week'] ?? json['dayOfWeek']),
      startTime: (json['start_time'] ?? json['startTime'] ?? '').toString(),
      endTime: (json['end_time'] ?? json['endTime'] ?? '').toString(),
      className: (json['class_name'] ?? json['className'] ?? '').toString(),
      classType: (json['class_type'] ?? json['classType'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'day_of_week': dayOfWeek,
      'start_time': startTime,
      'end_time': endTime,
      'class_name': className,
      'class_type': classType,
    };
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }

    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
