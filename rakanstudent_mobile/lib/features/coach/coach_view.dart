import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/task_model.dart';
import '../../services/api_service.dart';
import '../focus/focus_view.dart';
import 'moodle_calendar_import.dart';

enum _CoachMode { deadline, deepWork, quickWin }

class _CoachBreakdown {
  const _CoachBreakdown({
    required this.strategy,
    required this.coachCall,
    required this.contextLine,
    required this.blocks,
  });

  final String strategy;
  final String coachCall;
  final String contextLine;
  final List<_CoachWorkBlock> blocks;
}

class _CoachWorkBlock {
  const _CoachWorkBlock({
    required this.label,
    required this.minutes,
    required this.action,
    required this.output,
  });

  final String label;
  final int minutes;
  final String action;
  final String output;
}

class CoachView extends StatefulWidget {
  const CoachView({
    super.key,
    ApiService? apiService,
    @visibleForTesting this.fetchTasks,
    @visibleForTesting this.fetchOnInit = true,
  }) : _apiService = apiService;

  final ApiService? _apiService;
  final Future<List<Map<String, dynamic>>> Function()? fetchTasks;
  final bool fetchOnInit;

  @override
  State<CoachView> createState() => _CoachViewState();
}

class _CoachViewState extends State<CoachView> {
  late final ApiService _apiService = widget._apiService ?? ApiService();

  List<Task> _tasks = const <Task>[];
  bool _isLoading = true;
  Object? _error;
  _CoachMode _selectedMode = _CoachMode.deadline;
  String? _selectedTaskId;
  int _currentCoachStep = 0;
  bool _isImportingMoodle = false;
  // Only ICS file import is supported

  @override
  void initState() {
    super.initState();
    ApiService.taskMutationNotifier.addListener(_handleTaskMutation);
    if (widget.fetchOnInit) {
      _loadTasks();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    ApiService.taskMutationNotifier.removeListener(_handleTaskMutation);
    super.dispose();
  }

  void _handleTaskMutation() {
    if (mounted) {
      _loadTasks();
    }
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final rows = await (widget.fetchTasks?.call() ?? _apiService.getTasks());
      final tasks = _dedupeTasks(
        rows.map(Task.fromJson).toList(growable: false),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = tasks;
        _isLoading = false;
        if (!_hasActiveTaskWithId(tasks, _selectedTaskId)) {
          _selectedTaskId = _firstActiveTaskId(tasks);
          _currentCoachStep = 0;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  bool _hasActiveTaskWithId(List<Task> tasks, String? id) {
    if (id == null) {
      return false;
    }

    return tasks.any((task) => !task.isCompleted && task.id == id);
  }

  String? _firstActiveTaskId(List<Task> tasks) {
    final activeTasks = tasks.where((task) => !task.isCompleted).toList();
    activeTasks.sort(_compareCoachPriority);
    return activeTasks.isEmpty ? null : activeTasks.first.id;
  }

  Task? _selectedTaskFrom(List<Task> activeTasks) {
    if (activeTasks.isEmpty) {
      return null;
    }

    final selectedId = _selectedTaskId;
    if (selectedId == null) {
      return activeTasks.first;
    }

    for (final task in activeTasks) {
      if (task.id == selectedId) {
        return task;
      }
    }

    return activeTasks.first;
  }

  void _selectTask(Task task) {
    setState(() {
      _selectedTaskId = task.id;
      _currentCoachStep = 0;
    });
  }

  void _moveCoachStep(int delta, int totalSteps) {
    if (totalSteps <= 0) {
      return;
    }

    setState(() {
      _currentCoachStep = (_currentCoachStep + delta).clamp(0, totalSteps - 1);
    });
  }

  List<Task> _dedupeTasks(List<Task> fetchedTasks) {
    final uniqueTasks = <String, Task>{};

    for (final task in fetchedTasks) {
      final normalizedId = task.id.trim();
      final fallbackKey = [
        task.title.trim().toLowerCase(),
        task.dueDate?.toUtc().toIso8601String() ?? '',
        task.createdAt.toUtc().toIso8601String(),
      ].join('|');
      final key = normalizedId.isEmpty ? fallbackKey : normalizedId;

      uniqueTasks[key] = task;
    }

    return uniqueTasks.values.toList(growable: false);
  }

  List<Task> get _activeTasks {
    final tasks = _tasks.where((task) => !task.isCompleted).toList();
    tasks.sort(_compareCoachPriority);
    return tasks;
  }

  int _compareCoachPriority(Task first, Task second) {
    final firstScore = _priorityScore(first);
    final secondScore = _priorityScore(second);
    if (firstScore != secondScore) {
      return secondScore.compareTo(firstScore);
    }

    final firstDue = first.dueDate;
    final secondDue = second.dueDate;
    if (firstDue == null && secondDue == null) {
      return first.createdAt.compareTo(second.createdAt);
    }
    if (firstDue == null) {
      return 1;
    }
    if (secondDue == null) {
      return -1;
    }
    return firstDue.compareTo(secondDue);
  }

  int _priorityScore(Task task) {
    final now = DateTime.now();
    final dueDate = task.dueDate;
    var score = 0;

    if (dueDate != null) {
      final hoursLeft = dueDate.difference(now).inHours;
      if (hoursLeft < 0) {
        score += 100;
      } else if (hoursLeft <= 24) {
        score += 80;
      } else if (hoursLeft <= 72) {
        score += 50;
      } else if (hoursLeft <= 168) {
        score += 25;
      }
    }

    final priority = task.priorityBand?.toLowerCase().trim();
    if (priority == 'high' || priority == 'urgent') {
      score += 40;
    } else if (priority == 'medium') {
      score += 20;
    } else if (priority == 'low') {
      score += 5;
    }

    final estimate = task.estimatedMinutes ?? 0;
    if (estimate > 0 && estimate <= 45) {
      score += 10;
    }

    if (_selectedMode == _CoachMode.deepWork && estimate >= 45) {
      score += 35;
    } else if (_selectedMode == _CoachMode.quickWin &&
        estimate > 0 &&
        estimate <= 25) {
      score += 45;
    }

    return score;
  }

  int _countOverdueTasks(List<Task> tasks) {
    final now = DateTime.now();
    return tasks.where((task) {
      final dueDate = task.dueDate;
      return dueDate != null && dueDate.isBefore(now);
    }).length;
  }

  int _countDueSoonTasks(List<Task> tasks) {
    final now = DateTime.now();
    final soon = now.add(const Duration(days: 3));
    return tasks.where((task) {
      final dueDate = task.dueDate;
      return dueDate != null &&
          !dueDate.isBefore(now) &&
          dueDate.isBefore(soon);
    }).length;
  }

  int _countHeavyTasks(List<Task> tasks) {
    return tasks.where((task) => (task.estimatedMinutes ?? 0) >= 60).length;
  }

  int _countQuickWins(List<Task> tasks) {
    return tasks.where((task) {
      final estimate = task.estimatedMinutes ?? 0;
      return estimate > 0 && estimate <= 25;
    }).length;
  }

  int _suggestedFocusMinutes(Task? task) {
    final estimate = task?.estimatedMinutes;
    if (estimate == null || estimate <= 0) {
      return 25;
    }

    if (estimate <= 20) {
      return 15;
    }
    if (estimate <= 45) {
      return 25;
    }
    if (estimate <= 75) {
      return 45;
    }
    return 60;
  }

  String _dueLabel(Task task) {
    final dueDate = task.dueDate;
    if (dueDate == null) {
      return 'No deadline yet';
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final days = dueDay.difference(today).inDays;

    if (days < 0) {
      return 'Overdue by ${days.abs()} day${days == -1 ? '' : 's'}';
    }
    if (days == 0) {
      return 'Due today';
    }
    if (days == 1) {
      return 'Due tomorrow';
    }
    return 'Due in $days days';
  }

  String _coachReason(Task task) {
    final priority = task.priorityBand?.trim();
    final due = _dueLabel(task);
    if (_selectedMode == _CoachMode.deepWork) {
      return '$due. Coach picked this for a deeper study block.';
    }
    if (_selectedMode == _CoachMode.quickWin) {
      return '$due. Coach picked this because it can build momentum quickly.';
    }
    if (priority != null && priority.isNotEmpty) {
      return '$due with $priority priority.';
    }
    return '$due. Start here to reduce academic load.';
  }

  String _briefingLine({
    required int overdue,
    required int dueSoon,
    required int heavy,
    required int quickWins,
    required Task? nextTask,
  }) {
    if (nextTask == null) {
      return 'No fires right now. Use this space to recover, plan tomorrow, or start a clean focus sprint.';
    }
    if (overdue > 0) {
      return 'Red alert: clear the overdue work first, then protect your next deadline.';
    }
    if (dueSoon > 0) {
      return 'Pressure window open: one focused sprint now prevents deadline chaos later.';
    }
    if (heavy > 0) {
      return 'Deep-work day: break the largest assignment before it becomes urgent.';
    }
    if (quickWins > 0) {
      return 'Momentum play: clear a fast task and reduce mental clutter.';
    }
    return 'Steady state: choose one meaningful block and keep the queue from drifting.';
  }

  _CoachBreakdown _buildTaskBreakdown(Task? task) {
    if (task == null) {
      return const _CoachBreakdown(
        strategy: 'Recovery plan',
        coachCall:
            'You do not need more pressure right now. Use the clear window to make the next study session easier.',
        contextLine: 'No active task selected | prepare the next session',
        blocks: [
          _CoachWorkBlock(
            label: 'Scan',
            minutes: 10,
            action:
                'Check whether any class, assignment, or reading is missing a deadline.',
            output: 'A clean list with no floating obligations.',
          ),
          _CoachWorkBlock(
            label: 'Prep',
            minutes: 15,
            action:
                'Choose tomorrow\'s first task and open the needed material now.',
            output: 'A low-friction starting point for the next session.',
          ),
        ],
      );
    }

    final estimate = task.estimatedMinutes ?? 0;
    final dueDate = task.dueDate;
    final now = DateTime.now();
    final isOverdue = dueDate?.isBefore(now) ?? false;
    final isDueSoon =
        dueDate != null && !isOverdue && dueDate.difference(now).inHours <= 24;
    final text = '${task.title} ${task.notes ?? ''}'.toLowerCase();
    final isWriting = _containsAny(text, const [
      'essay',
      'report',
      'paper',
      'write',
      'reflection',
      'proposal',
    ]);
    final isStudy = _containsAny(text, const [
      'exam',
      'quiz',
      'study',
      'review',
      'revise',
      'test',
    ]);
    final isProblemSet = _containsAny(text, const [
      'problem',
      'worksheet',
      'assignment',
      'homework',
      'lab',
      'database',
      'math',
    ]);
    final contextLine = _contextLine(
      task,
      isWriting: isWriting,
      isStudy: isStudy,
      isProblemSet: isProblemSet,
    );
    final moodleState = _moodleState(task);
    if (moodleState.hasFeedback) {
      return _moodleFeedbackBreakdown(task, contextLine: contextLine);
    }
    if (moodleState.isSubmitted) {
      return _moodleSubmittedBreakdown(task, contextLine: contextLine);
    }
    final deliverables = _extractDeliverables(task);

    if (deliverables.length >= 2) {
      return _deliverableBreakdown(
        task,
        deliverables: deliverables,
        contextLine: contextLine,
      );
    }

    if (isOverdue) {
      return _overdueBreakdown(task, contextLine: contextLine);
    }
    if (_selectedMode == _CoachMode.quickWin ||
        estimate > 0 && estimate <= 25) {
      return _quickWinBreakdown(task, contextLine: contextLine);
    }
    if (isDueSoon) {
      return _deadlineBreakdown(
        task,
        isWriting: isWriting,
        isStudy: isStudy,
        isProblemSet: isProblemSet,
        contextLine: contextLine,
      );
    }
    if (_selectedMode == _CoachMode.deepWork || estimate >= 60) {
      return _deepWorkBreakdown(
        task,
        isWriting: isWriting,
        isStudy: isStudy,
        isProblemSet: isProblemSet,
        contextLine: contextLine,
      );
    }
    return _standardBreakdown(
      task,
      isWriting: isWriting,
      isStudy: isStudy,
      isProblemSet: isProblemSet,
      contextLine: contextLine,
    );
  }

  bool _containsAny(String text, List<String> terms) {
    return terms.any(text.contains);
  }

  ({bool isSubmitted, bool hasFeedback}) _moodleState(Task task) {
    final notes = (task.notes ?? '').toLowerCase();
    final isSubmitted =
        notes.contains('submission status: submitted') ||
        notes.contains('submission status: graded') ||
        notes.contains('submission status: reopened') ||
        notes.contains('submission status: draft') == false &&
            notes.contains('grade:');
    final hasFeedback = notes.contains('feedback:') || notes.contains('grade:');
    return (isSubmitted: isSubmitted, hasFeedback: hasFeedback);
  }

  String _taskKindLabel({
    required bool isWriting,
    required bool isStudy,
    required bool isProblemSet,
  }) {
    if (isWriting) {
      return 'writing task';
    }
    if (isStudy) {
      return 'study task';
    }
    if (isProblemSet) {
      return 'problem-solving task';
    }
    return 'execution task';
  }

  String _taskPressureLabel(Task task) {
    final dueDate = task.dueDate;
    if (dueDate == null) {
      return 'no deadline captured';
    }

    final hoursLeft = dueDate.difference(DateTime.now()).inHours;
    if (hoursLeft < 0) {
      return 'overdue';
    }
    if (hoursLeft <= 24) {
      return 'due within 24 hours';
    }
    if (hoursLeft <= 72) {
      return 'due within 3 days';
    }
    return _dueLabel(task).toLowerCase();
  }

  String _focusKeywords(Task task) {
    final text = '${task.title} ${task.notes ?? ''}'.toLowerCase();
    final matches = <String>[];
    const keywords = {
      'sql': 'SQL',
      'database': 'database',
      'schema': 'schema',
      'join': 'joins',
      'essay': 'essay',
      'report': 'report',
      'exam': 'exam',
      'quiz': 'quiz',
      'lab': 'lab',
      'lecture': 'lecture',
      'slides': 'slides',
      'reading': 'reading',
      'homework': 'homework',
    };

    for (final entry in keywords.entries) {
      if (text.contains(entry.key) && !matches.contains(entry.value)) {
        matches.add(entry.value);
      }
      if (matches.length == 3) {
        break;
      }
    }

    if (matches.isEmpty) {
      return 'the required output';
    }
    return matches.join(', ');
  }

  String _contextLine(
    Task task, {
    required bool isWriting,
    required bool isStudy,
    required bool isProblemSet,
  }) {
    final kind = _taskKindLabel(
      isWriting: isWriting,
      isStudy: isStudy,
      isProblemSet: isProblemSet,
    );
    final priority = task.priorityBand?.trim();
    final estimate = task.estimatedMinutes;
    final parts = <String>[
      kind,
      _taskPressureLabel(task),
      'focus: ${_focusKeywords(task)}',
    ];

    if (priority != null && priority.isNotEmpty) {
      parts.add('$priority priority');
    }
    if (estimate != null && estimate > 0) {
      parts.add('$estimate min estimate');
    }

    return parts.join(' | ');
  }

  List<String> _extractDeliverables(Task task) {
    final source = '${task.title}\n${task.notes ?? ''}'.toLowerCase();
    final deliverables = <String>[];
    const candidates = {
      'erd': 'ERD diagram',
      'diagram': 'diagram',
      'schema': 'schema',
      'sql': 'SQL queries',
      'query': 'queries',
      'queries': 'queries',
      'report': 'report',
      'reflection': 'reflection',
      'presentation': 'presentation',
      'slides': 'slides',
      'code': 'code',
      'implementation': 'implementation',
      'test': 'testing evidence',
      'screenshots': 'screenshots',
      'pdf': 'PDF submission',
      'video': 'video submission',
      'dataset': 'dataset',
      'analysis': 'analysis',
      'references': 'references',
      'bibliography': 'bibliography',
    };

    for (final entry in candidates.entries) {
      if (source.contains(entry.key) && !deliverables.contains(entry.value)) {
        deliverables.add(entry.value);
      }
    }

    return _dedupeDeliverables(deliverables).take(5).toList(growable: false);
  }

  List<String> _dedupeDeliverables(List<String> deliverables) {
    final result = List<String>.from(deliverables);
    if (result.contains('ERD diagram')) {
      result.remove('diagram');
    }
    if (result.contains('SQL queries')) {
      result.remove('queries');
    }
    return result;
  }

  _CoachBreakdown _deliverableBreakdown(
    Task task, {
    required List<String> deliverables,
    required String contextLine,
  }) {
    final blocks = <_CoachWorkBlock>[
      _CoachWorkBlock(
        label: 'Map Deliverables',
        minutes: 8,
        action:
            'Open ${task.title} and confirm these deliverables: ${deliverables.join(', ')}.',
        output: 'A checked list of what Moodle expects you to submit.',
      ),
    ];

    for (final deliverable in deliverables.take(4)) {
      blocks.add(
        _CoachWorkBlock(
          label: _titleCase(deliverable),
          minutes: _minutesForDeliverable(deliverable),
          action:
              'Work only on the $deliverable for ${task.title}. Do not switch deliverables until there is a visible output.',
          output: 'A usable $deliverable draft exists.',
        ),
      );
    }

    blocks.add(
      const _CoachWorkBlock(
        label: 'Submission Check',
        minutes: 10,
        action:
            'Compare every deliverable against Moodle instructions, file format, and upload requirements.',
        output: 'Everything needed for upload is present and named clearly.',
      ),
    );

    return _CoachBreakdown(
      strategy: 'Moodle deliverables',
      coachCall:
          'Coach found concrete deliverables in the Moodle description. Work through them one by one instead of treating this as one vague task.',
      contextLine: '$contextLine | deliverables: ${deliverables.join(', ')}',
      blocks: blocks,
    );
  }

  _CoachBreakdown _moodleSubmittedBreakdown(
    Task task, {
    required String contextLine,
  }) {
    return _CoachBreakdown(
      strategy: 'Submitted - verify only',
      coachCall:
          'Moodle shows this work is submitted. Do not keep spending full work blocks here unless submission details are wrong.',
      contextLine: '$contextLine | Moodle status: submitted',
      blocks: [
        _CoachWorkBlock(
          label: 'Confirm Submission',
          minutes: 5,
          action:
              'Open Moodle for ${task.title} and confirm the submitted file, timestamp, and status are correct.',
          output:
              'Submission is confirmed, or you know exactly what is missing.',
        ),
        const _CoachWorkBlock(
          label: 'Capture Follow-Up',
          minutes: 5,
          action:
              'If anything is missing, write the one repair action. If not, move to another task.',
          output: 'This task is closed or has one small follow-up.',
        ),
      ],
    );
  }

  _CoachBreakdown _moodleFeedbackBreakdown(
    Task task, {
    required String contextLine,
  }) {
    final feedback = _extractMoodleNoteValue(task, 'Feedback');
    final grade = _extractMoodleNoteValue(task, 'Grade');
    final feedbackFocus = feedback.isEmpty ? 'the Moodle feedback' : feedback;

    return _CoachBreakdown(
      strategy: 'Feedback review',
      coachCall:
          'Moodle feedback is available. The best move is to turn feedback into one improvement rule for the next assignment.',
      contextLine: [
        contextLine,
        if (grade.isNotEmpty) 'grade: $grade',
        'feedback available',
      ].join(' | '),
      blocks: [
        _CoachWorkBlock(
          label: 'Read Feedback',
          minutes: 8,
          action: 'Read the feedback for ${task.title}: $feedbackFocus',
          output: 'You can explain what the marker wanted improved.',
        ),
        const _CoachWorkBlock(
          label: 'Extract Rule',
          minutes: 7,
          action:
              'Write one reusable rule you will apply to the next assignment in this course.',
          output: 'One clear improvement rule exists.',
        ),
        const _CoachWorkBlock(
          label: 'Move On',
          minutes: 3,
          action:
              'Do not rework submitted material unless Moodle explicitly allows resubmission.',
          output: 'Attention is freed for the next active deadline.',
        ),
      ],
    );
  }

  String _extractMoodleNoteValue(Task task, String label) {
    final notes = task.notes ?? '';
    final prefix = '$label:';
    for (final line in notes.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
        return trimmed.substring(prefix.length).trim();
      }
    }
    return '';
  }

  int _minutesForDeliverable(String deliverable) {
    final normalized = deliverable.toLowerCase();
    if (normalized.contains('report') || normalized.contains('analysis')) {
      return 35;
    }
    if (normalized.contains('implementation') || normalized.contains('code')) {
      return 45;
    }
    if (normalized.contains('schema') || normalized.contains('sql')) {
      return 30;
    }
    return 25;
  }

  String _titleCase(String value) {
    return value
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  _CoachBreakdown _overdueBreakdown(Task task, {required String contextLine}) {
    final focus = _focusKeywords(task);
    return _CoachBreakdown(
      strategy: 'Rescue mode',
      coachCall:
          'This is no longer about doing it perfectly. Your job is to create a complete-enough version, submit or communicate, then recover control.',
      contextLine: contextLine,
      blocks: [
        _CoachWorkBlock(
          label: 'Triage',
          minutes: 8,
          action:
              'Open ${task.title} and circle the minimum required $focus output.',
          output: 'A clear minimum $focus version you can finish today.',
        ),
        _CoachWorkBlock(
          label: 'Build',
          minutes: 30,
          action:
              'Complete the missing $focus requirement before polishing anything.',
          output: 'A submittable $focus draft, solution, or response.',
        ),
        const _CoachWorkBlock(
          label: 'Close Loop',
          minutes: 7,
          action:
              'Submit it, message the instructor, or schedule the exact repair step.',
          output: 'The overdue loop is no longer open-ended.',
        ),
      ],
    );
  }

  _CoachBreakdown _deadlineBreakdown(
    Task task, {
    required bool isWriting,
    required bool isStudy,
    required bool isProblemSet,
    required String contextLine,
  }) {
    final focus = _focusKeywords(task);
    final coreAction =
        isWriting
            ? 'Write the roughest complete version of the hardest $focus section.'
            : isStudy
            ? 'Quiz yourself on the weakest $focus topic before rereading notes.'
            : isProblemSet
            ? 'Solve the hardest $focus question first and write the method beside it.'
            : 'Finish the highest-value $focus requirement first.';
    final coreOutput =
        isWriting
            ? 'A rough $focus section with all main points present.'
            : isStudy
            ? 'A list of weak $focus topics and corrected answers.'
            : isProblemSet
            ? 'One solved $focus model answer.'
            : 'The most important $focus part is no longer untouched.';

    return _CoachBreakdown(
      strategy: 'Deadline defense',
      coachCall:
          'The deadline is close enough that prioritization matters more than comfort. Attack the part that would hurt most if left unfinished.',
      contextLine: contextLine,
      blocks: [
        _CoachWorkBlock(
          label: 'Target',
          minutes: 5,
          action:
              'Choose the one $focus part of ${task.title} with the highest grade or deadline impact.',
          output: 'One target, not a list of possibilities.',
        ),
        _CoachWorkBlock(
          label: 'Attack',
          minutes: _suggestedFocusMinutes(task),
          action: coreAction,
          output: coreOutput,
        ),
        const _CoachWorkBlock(
          label: 'Buffer',
          minutes: 10,
          action:
              'Check instructions, file format, rubric, or submission path.',
          output: 'No last-minute technical surprise.',
        ),
      ],
    );
  }

  _CoachBreakdown _deepWorkBreakdown(
    Task task, {
    required bool isWriting,
    required bool isStudy,
    required bool isProblemSet,
    required String contextLine,
  }) {
    final focus = _focusKeywords(task);
    final action =
        isWriting
            ? 'Create the $focus outline, then draft the first ugly paragraph under each heading.'
            : isStudy
            ? 'Do active recall for $focus: close notes, answer from memory, then correct gaps.'
            : isProblemSet
            ? 'Solve the first difficult $focus item slowly and write the method beside it.'
            : 'Break the task into three visible deliverables and complete the first one.';
    final output =
        isWriting
            ? 'An outline plus rough starter text.'
            : isStudy
            ? 'A corrected weak-topic list.'
            : isProblemSet
            ? 'One solved model problem you can copy the method from.'
            : 'A finished first deliverable.';

    return _CoachBreakdown(
      strategy: 'Deep-work breakdown',
      coachCall:
          'This task is big enough to punish vague effort. Define the output, work in one protected block, then leave a breadcrumb for restart.',
      contextLine: contextLine,
      blocks: [
        _CoachWorkBlock(
          label: 'Define',
          minutes: 10,
          action: 'Write what “done for this session” means for ${task.title}.',
          output: 'A one-sentence session target.',
        ),
        _CoachWorkBlock(
          label: 'Deep Block',
          minutes: _suggestedFocusMinutes(task),
          action: action,
          output: output,
        ),
        const _CoachWorkBlock(
          label: 'Breadcrumb',
          minutes: 5,
          action:
              'Write the next exact action at the top of your notes before stopping.',
          output: 'A restart instruction for future you.',
        ),
      ],
    );
  }

  _CoachBreakdown _quickWinBreakdown(Task task, {required String contextLine}) {
    final minutes = task.estimatedMinutes ?? 15;
    final focus = _focusKeywords(task);
    return _CoachBreakdown(
      strategy: 'Quick-win finish',
      coachCall:
          'This is small enough to remove from your mental load right now. Treat it like a sprint, not a planning session.',
      contextLine: contextLine,
      blocks: [
        _CoachWorkBlock(
          label: 'Start',
          minutes: 2,
          action: 'Open ${task.title} and identify the $focus finish line.',
          output: 'You know exactly what done means for $focus.',
        ),
        _CoachWorkBlock(
          label: 'Finish',
          minutes: minutes.clamp(10, 25),
          action: 'Complete the task in one pass without switching apps.',
          output: 'The task is ready to mark done.',
        ),
        const _CoachWorkBlock(
          label: 'Verify',
          minutes: 3,
          action: 'Check the requirement once, then mark it complete.',
          output: 'Closed loop, no lingering doubt.',
        ),
      ],
    );
  }

  _CoachBreakdown _standardBreakdown(
    Task task, {
    required bool isWriting,
    required bool isStudy,
    required bool isProblemSet,
    required String contextLine,
  }) {
    final focus = _focusKeywords(task);
    final action =
        isWriting
            ? 'Make a quick $focus outline and draft the first section without editing.'
            : isStudy
            ? 'Turn $focus into five practice questions and answer them cold.'
            : isProblemSet
            ? 'Solve the first required $focus item and note the method you used.'
            : 'Define the deliverable and complete the first visible chunk.';

    return _CoachBreakdown(
      strategy: 'Focused progress',
      coachCall:
          'You do not need the whole task finished in one sitting. You need a clean first chunk that makes the next session obvious.',
      contextLine: contextLine,
      blocks: [
        _CoachWorkBlock(
          label: 'Clarify',
          minutes: 5,
          action:
              'Read the requirement for ${task.title} and define the expected output.',
          output: 'A clear finish line.',
        ),
        _CoachWorkBlock(
          label: 'Produce',
          minutes: _suggestedFocusMinutes(task),
          action: action,
          output: 'One visible piece of progress.',
        ),
        const _CoachWorkBlock(
          label: 'Next Step',
          minutes: 5,
          action: 'Write the next action before leaving the task.',
          output: 'A clear restart point.',
        ),
      ],
    );
  }

  String _modeTitle(_CoachMode mode) {
    return switch (mode) {
      _CoachMode.deadline => 'Deadline rescue',
      _CoachMode.deepWork => 'Deep work',
      _CoachMode.quickWin => 'Quick win',
    };
  }

  String _modeSubtitle(_CoachMode mode) {
    return switch (mode) {
      _CoachMode.deadline => 'Attack urgent due dates first',
      _CoachMode.deepWork => 'Prioritize longer academic blocks',
      _CoachMode.quickWin => 'Clear short tasks for momentum',
    };
  }

  IconData _modeIcon(_CoachMode mode) {
    return switch (mode) {
      _CoachMode.deadline => Icons.emergency_rounded,
      _CoachMode.deepWork => Icons.self_improvement_rounded,
      _CoachMode.quickWin => Icons.flash_on_rounded,
    };
  }

  Future<void> _startFocusSession(Task? task) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) =>
                FocusView(initialDurationMinutes: _suggestedFocusMinutes(task)),
      ),
    );
  }

  Future<void> _importMoodleCalendar() async {
    if (_isImportingMoodle) {
      return;
    }

    setState(() {
      _isImportingMoodle = true;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['ics'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;
      final path = file.path;
      final contents =
          bytes != null
              ? utf8.decode(bytes, allowMalformed: true)
              : path != null
              ? await File(path).readAsString()
              : '';

      if (contents.trim().isEmpty) {
        _showSnackBar('Selected Moodle ICS file is empty.');
        return;
      }

      await _importMoodleIcsContent(contents);
    } catch (error) {
      _showSnackBar('Unable to import Moodle calendar: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isImportingMoodle = false;
        });
      }
    }
  }

  Future<void> _importMoodleIcsContent(String ics) async {
    final result = parseMoodleCalendarIcs(ics);
    if (result.events.isEmpty) {
      _showSnackBar('No upcoming Moodle events found in that calendar.');
      return;
    }

    var imported = 0;
    for (final event in result.events.take(30)) {
      await _apiService.createTask(
        {
          'title': event.title,
          'description': event.notes,
          'priorityLevel': 'High',
          'dueDate': event.dueAt.toIso8601String(),
          'status': 'Pending',
        },
        taskType: 'moodle',
        notes: event.notes,
      );
      imported++;
    }

    await _loadTasks();
    _showSnackBar(
      'Imported $imported Moodle event${imported == 1 ? '' : 's'} as tasks.',
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final activeTasks = _activeTasks;
    final selectedTask = _selectedTaskFrom(activeTasks);
    final overdueTasks = _countOverdueTasks(activeTasks);
    final dueSoonTasks = _countDueSoonTasks(activeTasks);
    final heavyTasks = _countHeavyTasks(activeTasks);
    final quickWins = _countQuickWins(activeTasks);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadTasks,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 128),
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 120),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _buildErrorState(context)
              else ...[
                _buildMissionModeSelector(context),
                const SizedBox(height: 24),
                _buildMoodleImportCard(context),
                const SizedBox(height: 24),
                _buildTaskChooser(context, activeTasks, selectedTask),
                const SizedBox(height: 24),
                _buildCoachBreakdownCard(context, selectedTask),
                const SizedBox(height: 24),
                _buildAfterThis(
                  context,
                  activeTasks
                      .where((task) => task.id != selectedTask?.id)
                      .take(2)
                      .toList(),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: colorScheme.tertiary.withValues(alpha: 0.26),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_rounded,
                        color: colorScheme.onTertiaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _briefingLine(
                            overdue: overdueTasks,
                            dueSoon: dueSoonTasks,
                            heavy: heavyTasks,
                            quickWins: quickWins,
                            nextTask: selectedTask,
                          ),
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onTertiaryContainer,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMissionModeSelector(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mission Mode',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: _CoachMode.values
                .map((mode) {
                  final selected = _selectedMode == mode;
                  final colorScheme = theme.colorScheme;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedMode = mode;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 168,
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:
                            selected
                                ? colorScheme.primary
                                : colorScheme.surface,
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color:
                              selected
                                  ? colorScheme.primary
                                  : colorScheme.outline.withValues(alpha: 0.32),
                        ),
                        boxShadow:
                            selected
                                ? [
                                  BoxShadow(
                                    color: colorScheme.primary.withValues(
                                      alpha: 0.28,
                                    ),
                                    blurRadius: 22,
                                    offset: const Offset(0, 12),
                                  ),
                                ]
                                : const [],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _modeIcon(mode),
                            color:
                                selected
                                    ? colorScheme.onPrimary
                                    : colorScheme.primary,
                          ),
                          const Spacer(),
                          Text(
                            _modeTitle(mode),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color:
                                  selected
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _modeSubtitle(mode),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color:
                                  selected
                                      ? colorScheme.onPrimary.withValues(
                                        alpha: 0.76,
                                      )
                                      : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                })
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _buildTaskChooser(
    BuildContext context,
    List<Task> tasks,
    Task? selectedTask,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.touch_app_rounded, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Choose What To Coach',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Pick the task you want help completing. The coach will walk you through it one step at a time.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          if (tasks.isEmpty)
            Text(
              'No active tasks to coach yet.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            SizedBox(
              height: 132,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: tasks.length,
                itemBuilder: (context, index) {
                  final task = tasks[index];
                  final selected = task.id == selectedTask?.id;
                  return _buildTaskChoiceCard(
                    context,
                    task,
                    selected: selected,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMoodleImportCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.secondary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(Icons.school_rounded, color: colorScheme.secondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Moodle Calendar',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Upload an ICS file exported from your Moodle calendar to import deadlines.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSecondaryContainer.withValues(
                      alpha: 0.78,
                    ),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          _isImportingMoodle ? null : _importMoodleCalendar,
                      icon:
                          _isImportingMoodle
                              ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Icon(Icons.upload_file_rounded),
                      label: Text(
                        _isImportingMoodle ? 'Importing...' : 'Upload ICS',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskChoiceCard(
    BuildContext context,
    Task task, {
    required bool selected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => _selectTask(task),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 226,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              selected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color:
                selected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.48),
          ),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ]
                  : const [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: selected ? colorScheme.onPrimary : colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _dueLabel(task),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          selected
                              ? colorScheme.onPrimary.withValues(alpha: 0.78)
                              : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
                fontWeight: FontWeight.w900,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              task.estimatedMinutes == null || task.estimatedMinutes! <= 0
                  ? 'Coach will estimate the first sprint'
                  : '${task.estimatedMinutes} min estimate',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color:
                    selected
                        ? colorScheme.onPrimary.withValues(alpha: 0.72)
                        : colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.62 : 0.86,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              Icons.psychology_alt_rounded,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RAKAN COMMAND CENTER',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Study Coach',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Refresh coach',
            onPressed: _loadTasks,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildCoachBreakdownCard(BuildContext context, Task? task) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final breakdown = _buildTaskBreakdown(task);
    final stepIndex = _currentCoachStep.clamp(0, breakdown.blocks.length - 1);
    final activeBlock = breakdown.blocks[stepIndex];
    final nextBlock =
        stepIndex + 1 < breakdown.blocks.length
            ? breakdown.blocks[stepIndex + 1]
            : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.account_tree_rounded,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Step-by-Step Coach',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      breakdown.strategy,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Coach read: ${breakdown.contextLine}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              breakdown.coachCall,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 22),
          _buildActiveCoachStep(
            context,
            block: activeBlock,
            step: stepIndex + 1,
            totalSteps: breakdown.blocks.length,
            nextBlock: nextBlock,
            task: task,
          ),
          const SizedBox(height: 20),
          _buildStepProgressRail(context, breakdown.blocks, stepIndex),
        ],
      ),
    );
  }

  Widget _buildActiveCoachStep(
    BuildContext context, {
    required _CoachWorkBlock block,
    required int step,
    required int totalSteps,
    required _CoachWorkBlock? nextBlock,
    required Task? task,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.95),
            colorScheme.tertiary.withValues(alpha: 0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.onPrimary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  'STEP $step OF $totalSteps',
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${block.minutes} min',
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            block.label,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onPrimary,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            block.action,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onPrimary.withValues(alpha: 0.88),
              fontWeight: FontWeight.w700,
              height: 1.32,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.onPrimary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: colorScheme.onPrimary.withValues(alpha: 0.16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OUTPUT BEFORE MOVING ON',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onPrimary.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  block.output,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w900,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Move on only after you have the output above. If not, stay on this step.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onPrimary.withValues(alpha: 0.74),
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          if (nextBlock != null) ...[
            const SizedBox(height: 10),
            Text(
              'Next: ${nextBlock.label} - ${nextBlock.output}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onPrimary.withValues(alpha: 0.76),
                fontWeight: FontWeight.w700,
                height: 1.28,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      step == 1 ? null : () => _moveCoachStep(-1, totalSteps),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.onPrimary,
                    disabledForegroundColor: colorScheme.onPrimary.withValues(
                      alpha: 0.38,
                    ),
                    side: BorderSide(
                      color: colorScheme.onPrimary.withValues(
                        alpha: step == 1 ? 0.18 : 0.54,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      step == totalSteps
                          ? () => _startFocusSession(task)
                          : () => _moveCoachStep(1, totalSteps),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.onPrimary,
                    foregroundColor: colorScheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  icon: Icon(
                    step == totalSteps
                        ? Icons.play_arrow_rounded
                        : Icons.arrow_forward_rounded,
                  ),
                  label: Text(step == totalSteps ? 'Start Focus' : 'Next Step'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepProgressRail(
    BuildContext context,
    List<_CoachWorkBlock> blocks,
    int activeIndex,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FULL BREAKDOWN',
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < blocks.length; index++)
          _buildProgressStepButton(
            context,
            block: blocks[index],
            index: index,
            active: index == activeIndex,
          ),
      ],
    );
  }

  Widget _buildProgressStepButton(
    BuildContext context, {
    required _CoachWorkBlock block,
    required int index,
    required bool active,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() {
            _currentCoachStep = index;
          });
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                active
                    ? colorScheme.primary.withValues(alpha: 0.1)
                    : colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.32,
                    ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  active
                      ? colorScheme.primary.withValues(alpha: 0.38)
                      : colorScheme.outlineVariant.withValues(alpha: 0.36),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor:
                    active
                        ? colorScheme.primary
                        : colorScheme.surfaceContainerHighest,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color:
                        active
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${block.minutes} min - ${block.output}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAfterThis(BuildContext context, List<Task> tasks) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.34),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'After This',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              const Icon(Icons.route_rounded),
            ],
          ),
          const SizedBox(height: 14),
          if (tasks.isEmpty)
            Text(
              'No second move needed. Finish the current mission, then reassess.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (var index = 0; index < tasks.length; index++)
              _buildAfterThisStep(
                context,
                task: tasks[index],
                step: index + 1,
                isLast: index == tasks.length - 1,
              ),
        ],
      ),
    );
  }

  Widget _buildAfterThisStep(
    BuildContext context, {
    required Task task,
    required int step,
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$step',
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    color: colorScheme.outline.withValues(alpha: 0.28),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _coachReason(task),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: () => _startFocusSession(task),
            child: const Text('Focus'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(height: 12),
          Text(
            'Coach could not load tasks',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Check the backend connection and try refreshing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _loadTasks,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
