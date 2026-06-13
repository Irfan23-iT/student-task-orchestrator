class MoodleCalendarEvent {
  const MoodleCalendarEvent({
    required this.title,
    required this.dueAt,
    this.description,
    this.course,
    this.url,
  });

  final String title;
  final DateTime dueAt;
  final String? description;
  final String? course;
  final String? url;

  String get notes {
    final lines = <String>['Imported from Moodle calendar.'];
    if (course != null && course!.trim().isNotEmpty) {
      lines.add('Course: $course');
    }
    if (description != null && description!.trim().isNotEmpty) {
      lines.add(description!.trim());
    }
    if (url != null && url!.trim().isNotEmpty) {
      lines.add('Moodle link: $url');
    }
    return lines.join('\n');
  }
}

class MoodleCalendarImportResult {
  const MoodleCalendarImportResult({
    required this.events,
    required this.skippedPastEvents,
  });

  final List<MoodleCalendarEvent> events;
  final int skippedPastEvents;
}

MoodleCalendarImportResult parseMoodleCalendarIcs(String ics, {DateTime? now}) {
  final referenceTime = now ?? DateTime.now();
  final events = <MoodleCalendarEvent>[];
  var skippedPastEvents = 0;

  for (final block in _eventBlocks(ics)) {
    final fields = _parseEventFields(block);
    final rawTitle = fields['SUMMARY']?.trim();
    final dueAt = _parseIcsDateTime(
      fields['DUE'] ?? fields['DTEND'] ?? fields['DTSTART'],
    );

    if (rawTitle == null || rawTitle.isEmpty || dueAt == null) {
      continue;
    }

    if (dueAt.isBefore(referenceTime.subtract(const Duration(hours: 12)))) {
      skippedPastEvents++;
      continue;
    }

    events.add(
      MoodleCalendarEvent(
        title: _cleanMoodleTitle(rawTitle),
        dueAt: dueAt,
        description: fields['DESCRIPTION']?.trim(),
        course: fields['CATEGORIES']?.trim(),
        url: fields['URL']?.trim(),
      ),
    );
  }

  events.sort((first, second) => first.dueAt.compareTo(second.dueAt));
  return MoodleCalendarImportResult(
    events: events,
    skippedPastEvents: skippedPastEvents,
  );
}

List<List<String>> _eventBlocks(String ics) {
  final blocks = <List<String>>[];
  final current = <String>[];
  var insideEvent = false;

  for (final line in _unfoldIcsLines(ics)) {
    if (line == 'BEGIN:VEVENT') {
      insideEvent = true;
      current.clear();
      continue;
    }
    if (line == 'END:VEVENT') {
      if (insideEvent) {
        blocks.add(List<String>.from(current));
      }
      insideEvent = false;
      current.clear();
      continue;
    }
    if (insideEvent) {
      current.add(line);
    }
  }

  return blocks;
}

List<String> _unfoldIcsLines(String ics) {
  final normalized = ics.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final unfolded = <String>[];

  for (final line in normalized.split('\n')) {
    if ((line.startsWith(' ') || line.startsWith('\t')) &&
        unfolded.isNotEmpty) {
      unfolded[unfolded.length - 1] += line.substring(1);
    } else {
      unfolded.add(line.trimRight());
    }
  }

  return unfolded;
}

Map<String, String> _parseEventFields(List<String> lines) {
  final fields = <String, String>{};

  for (final line in lines) {
    final separator = line.indexOf(':');
    if (separator <= 0) {
      continue;
    }

    final rawName = line.substring(0, separator);
    final name = rawName.split(';').first.toUpperCase();
    final value = _unescapeIcsValue(line.substring(separator + 1));
    fields[name] = value;
  }

  return fields;
}

String _unescapeIcsValue(String value) {
  return value
      .replaceAll('\\n', '\n')
      .replaceAll('\\N', '\n')
      .replaceAll('\\,', ',')
      .replaceAll('\\;', ';')
      .replaceAll('\\\\', '\\')
      .trim();
}

DateTime? _parseIcsDateTime(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  final normalized = value.trim();
  if (RegExp(r'^\d{8}$').hasMatch(normalized)) {
    return DateTime(
      int.parse(normalized.substring(0, 4)),
      int.parse(normalized.substring(4, 6)),
      int.parse(normalized.substring(6, 8)),
      23,
      59,
    );
  }

  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$',
  ).firstMatch(normalized);
  if (match == null) {
    return DateTime.tryParse(normalized);
  }

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final isUtc = match.group(7) == 'Z';

  if (isUtc) {
    return DateTime.utc(year, month, day, hour, minute, second).toLocal();
  }
  return DateTime(year, month, day, hour, minute, second);
}

String _cleanMoodleTitle(String title) {
  return title
      .replaceFirst(RegExp(r'^Assignment due:\s*', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^Quiz closes:\s*', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^Event:\s*', caseSensitive: false), '')
      .trim();
}
