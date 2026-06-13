import 'package:flutter_test/flutter_test.dart';
import 'package:rakanstudent_mobile/features/coach/moodle_assignment_import.dart';

void main() {
  test('parseMoodleAssignmentsResponse imports upcoming assignments', () {
    final response = {
      'courses': [
        {
          'fullname': 'Database Systems',
          'assignments': [
            {
              'name': 'SQL Schema Project',
              'duedate': 1782900000,
              'intro': '<p>Submit schema &amp; ERD.</p>',
              'cmid': 123,
              'submissions': [
                {'status': 'draft'},
              ],
              'grades': [
                {'gradefordisplay': '82 / 100'},
              ],
              'feedbackplugins': [
                {
                  'editorfields': [
                    {'text': '<p>Explain your schema assumptions.</p>'},
                  ],
                },
              ],
            },
          ],
        },
      ],
    };

    final result = parseMoodleAssignmentsResponse(
      response,
      now: DateTime.utc(2026, 6, 30),
    );

    expect(result.assignments, hasLength(1));
    final assignment = result.assignments.single;
    expect(assignment.title, 'SQL Schema Project');
    expect(assignment.course, 'Database Systems');
    expect(assignment.notes, contains('Submit schema & ERD.'));
    expect(assignment.notes, contains('Submission status: draft'));
    expect(assignment.notes, contains('Grade: 82 / 100'));
    expect(
      assignment.notes,
      contains('Feedback: Explain your schema assumptions.'),
    );
    expect(assignment.url, 'mod/assign/view.php?id=123');
  });

  test(
    'parseMoodleAssignmentsResponse skips assignments without due dates',
    () {
      final response = {
        'courses': [
          {
            'fullname': 'No Due Course',
            'assignments': [
              {'name': 'Open ended task', 'duedate': 0},
            ],
          },
        ],
      };

      final result = parseMoodleAssignmentsResponse(response);

      expect(result.assignments, isEmpty);
    },
  );
}
