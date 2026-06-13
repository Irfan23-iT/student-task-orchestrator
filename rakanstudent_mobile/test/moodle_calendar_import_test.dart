import 'package:flutter_test/flutter_test.dart';
import 'package:rakanstudent_mobile/features/coach/moodle_calendar_import.dart';

void main() {
  test('parseMoodleCalendarIcs imports upcoming Moodle events', () {
    const ics = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
SUMMARY:Assignment due: Database Project
DTSTART:20260701T090000Z
DESCRIPTION:Submit SQL schema\\nand ERD diagram.
CATEGORIES:Database Systems
URL:https://moodle.example/mod/assign/view.php?id=123
END:VEVENT
BEGIN:VEVENT
SUMMARY:Quiz closes: Networks Quiz 1
DTSTART;VALUE=DATE:20260705
DESCRIPTION:Review lecture slides.
CATEGORIES:Computer Networks
END:VEVENT
END:VCALENDAR
''';

    final result = parseMoodleCalendarIcs(ics, now: DateTime.utc(2026, 6, 30));

    expect(result.events, hasLength(2));
    expect(result.events.first.title, 'Database Project');
    expect(result.events.first.course, 'Database Systems');
    expect(result.events.first.notes, contains('SQL schema'));
    expect(
      result.events.first.notes,
      contains('Moodle link: https://moodle.example'),
    );
    expect(result.events[1].title, 'Networks Quiz 1');
    expect(result.events[1].dueAt.hour, 23);
    expect(result.events[1].dueAt.minute, 59);
  });

  test('parseMoodleCalendarIcs skips old events', () {
    const ics = '''
BEGIN:VCALENDAR
BEGIN:VEVENT
SUMMARY:Assignment due: Old Work
DTSTART:20260101T090000Z
END:VEVENT
END:VCALENDAR
''';

    final result = parseMoodleCalendarIcs(ics, now: DateTime.utc(2026, 6, 30));

    expect(result.events, isEmpty);
    expect(result.skippedPastEvents, 1);
  });
}
