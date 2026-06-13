class MoodleAssignmentImportResult {
  const MoodleAssignmentImportResult({required this.assignments});

  final List<MoodleAssignmentTask> assignments;
}

class MoodleAssignmentTask {
  const MoodleAssignmentTask({
    required this.title,
    required this.dueAt,
    required this.course,
    required this.notes,
    this.url,
  });

  final String title;
  final DateTime dueAt;
  final String course;
  final String notes;
  final String? url;
}

MoodleAssignmentImportResult parseMoodleAssignmentsResponse(
  Map<String, dynamic> json, {
  DateTime? now,
}) {
  final referenceTime = now ?? DateTime.now();
  final assignments = <MoodleAssignmentTask>[];
  final courses = json['courses'] as List<dynamic>? ?? const [];

  for (final rawCourse in courses) {
    if (rawCourse is! Map) {
      continue;
    }

    final course = Map<String, dynamic>.from(rawCourse);
    final courseName = _asText(course['fullname'] ?? course['shortname']);
    final rawAssignments = course['assignments'] as List<dynamic>? ?? const [];

    for (final rawAssignment in rawAssignments) {
      if (rawAssignment is! Map) {
        continue;
      }

      final assignment = Map<String, dynamic>.from(rawAssignment);
      final title = _asText(assignment['name']);
      final dueAt = _parseUnixSeconds(assignment['duedate']);
      if (title.isEmpty || dueAt == null) {
        continue;
      }
      if (dueAt.isBefore(referenceTime.subtract(const Duration(hours: 12)))) {
        continue;
      }

      final intro = _stripHtml(_asText(assignment['intro']));
      final cmid = _asText(assignment['cmid']);
      final url = cmid.isEmpty ? null : 'mod/assign/view.php?id=$cmid';

      assignments.add(
        MoodleAssignmentTask(
          title: title,
          dueAt: dueAt,
          course: courseName.isEmpty ? 'Moodle course' : courseName,
          url: url,
          notes: _assignmentNotes(
            course: courseName,
            intro: intro,
            submissionStatus: _submissionStatus(assignment),
            grade: _grade(assignment),
            feedback: _feedback(assignment),
            url: url,
          ),
        ),
      );
    }
  }

  assignments.sort((first, second) => first.dueAt.compareTo(second.dueAt));
  return MoodleAssignmentImportResult(assignments: assignments);
}

String _assignmentNotes({
  required String course,
  required String intro,
  required String submissionStatus,
  required String grade,
  required String feedback,
  required String? url,
}) {
  final lines = <String>['Imported from Moodle assignments.'];
  if (course.trim().isNotEmpty) {
    lines.add('Course: $course');
  }
  if (submissionStatus.trim().isNotEmpty) {
    lines.add('Submission status: $submissionStatus');
  }
  if (grade.trim().isNotEmpty) {
    lines.add('Grade: $grade');
  }
  if (feedback.trim().isNotEmpty) {
    lines.add('Feedback: $feedback');
  }
  if (intro.trim().isNotEmpty) {
    lines.add(intro.trim());
  }
  if (url != null && url.trim().isNotEmpty) {
    lines.add('Moodle path: $url');
  }
  return lines.join('\n');
}

String _submissionStatus(Map<String, dynamic> assignment) {
  final submissions = assignment['submissions'] as List<dynamic>? ?? const [];
  if (submissions.isEmpty) {
    return '';
  }

  final first = submissions.first;
  if (first is! Map) {
    return '';
  }
  return _asText(first['status']);
}

String _grade(Map<String, dynamic> assignment) {
  final directGrade = _asText(
    assignment['grade'] ?? assignment['gradefordisplay'],
  );
  if (directGrade.isNotEmpty) {
    return directGrade;
  }

  final grades = assignment['grades'] as List<dynamic>? ?? const [];
  for (final rawGrade in grades) {
    if (rawGrade is! Map) {
      continue;
    }
    final grade = Map<String, dynamic>.from(rawGrade);
    final value = _asText(
      grade['gradefordisplay'] ?? grade['str_grade'] ?? grade['grade'],
    );
    if (value.isNotEmpty && value != '-1') {
      return value;
    }
  }

  return '';
}

String _feedback(Map<String, dynamic> assignment) {
  final directFeedback = _stripHtml(
    _asText(assignment['feedback'] ?? assignment['feedbackcomments']),
  );
  if (directFeedback.isNotEmpty) {
    return directFeedback;
  }

  final plugins = assignment['feedbackplugins'] as List<dynamic>? ?? const [];
  for (final rawPlugin in plugins) {
    if (rawPlugin is! Map) {
      continue;
    }
    final plugin = Map<String, dynamic>.from(rawPlugin);
    final editorFields = plugin['editorfields'] as List<dynamic>? ?? const [];
    for (final rawField in editorFields) {
      if (rawField is! Map) {
        continue;
      }
      final field = Map<String, dynamic>.from(rawField);
      final text = _stripHtml(_asText(field['text']));
      if (text.isNotEmpty) {
        return text;
      }
    }
  }

  return '';
}

DateTime? _parseUnixSeconds(Object? value) {
  final seconds = value is int ? value : int.tryParse('${value ?? ''}');
  if (seconds == null || seconds <= 0) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  ).toLocal();
}

String _stripHtml(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}

String _asText(Object? value) {
  return value?.toString().trim() ?? '';
}
