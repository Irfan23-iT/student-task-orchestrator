// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/task_model.dart';
import '../../screens/add_custom_task_screen.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import '../gacha/gacha_controller.dart';
import 'voice_capture_widget.dart';

class TasksView extends ConsumerStatefulWidget {
  const TasksView({
    super.key,
    this.refreshSignal = 0,
    @visibleForTesting this.fetchOnInit = true,
    @visibleForTesting this.enableVoiceCapture = true,
    @visibleForTesting this.enableCleanupVerification = true,
  });

  final int refreshSignal;
  final bool fetchOnInit;
  final bool enableVoiceCapture;
  final bool enableCleanupVerification;

  @override
  ConsumerState<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends ConsumerState<TasksView> {
  final ApiService _apiService = ApiService();

  List<Task> _tasks = const [];
  bool _isLoading = true;
  bool _isSyncingCalendar = false;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.initialize();
    ApiService.taskMutationNotifier.addListener(_handleTaskMutation);
    if (widget.fetchOnInit) {
      _fetchTasks();
    } else {
      _isLoading = false;
    }
    if (widget.enableCleanupVerification) {
      _runCleanupVerification();
    }
  }

  @override
  void dispose() {
    ApiService.taskMutationNotifier.removeListener(_handleTaskMutation);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TasksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshSignal != oldWidget.refreshSignal) {
      _fetchTasks();
    }
  }

  void _handleTaskMutation() {
    if (mounted) {
      _fetchTasks();
    }
  }

  void _showNetworkErrorSnackBar() {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cannot reach server right now. Please try again.'),
      ),
    );
  }

  Future<void> _fetchTasks() async {
    if (mounted) {
      setState(() {
        _tasks = const [];
        _isLoading = true;
      });
    }

    try {
      final response = await _apiService.getTasks();
      final tasks = _dedupeTasks(
        response.map(Task.fromJson).toList(growable: false),
      );
      await NotificationService.instance.scheduleTaskReminders(tasks);

      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } on SocketException {
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = const [];
        _isLoading = false;
      });
      _showNetworkErrorSnackBar();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = const [];
        _isLoading = false;
      });
    }
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

  Future<void> _runCleanupVerification() async {
    try {
      print('--- CODEX CLEANUP TEST START ---');
      await _apiService.getTasks();
      print('--- CODEX CLEANUP SUCCESS: Tasks fetched from API ---');
    } catch (e) {
      print('--- CODEX CLEANUP TEST FAILED: $e ---');
    }
  }

  Future<void> _handleVoiceTaskCreated(AiChatResponse response) async {
    if (!mounted) {
      return;
    }

    await _fetchTasks();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(response.message)));
  }

  Future<void> _createReminderForTask(Task task) async {
    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );

    if (!mounted) {
      return;
    }

    if (selectedDate == null) {
      return;
    }

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (!mounted) {
      return;
    }

    if (selectedTime == null) {
      return;
    }

    final reminderAt = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    if (reminderAt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a future reminder time.')),
      );
      return;
    }

    final reminderAtIso = reminderAt.toUtc().toIso8601String();
    final messenger = ScaffoldMessenger.of(context);
    final reminderDateLabel = MaterialLocalizations.of(
      context,
    ).formatShortDate(reminderAt);
    final reminderTimeLabel = selectedTime.format(context);

    try {
      await _apiService.createReminder(
        task.id,
        'Reminder: ${task.title}',
        reminderAtIso,
        taskType: 'task',
      );

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Reminder set for $reminderTimeLabel on $reminderDateLabel',
          ),
        ),
      );
    } on SocketException {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Unable to set reminder: $e')),
      );
    }
  }

  Future<void> _runReminderTest() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      print('--- CODEX REMINDER TEST START ---');

      if (_tasks.isEmpty) {
        throw Exception('No fetched tasks are available for reminder testing.');
      }

      final task = _tasks.first;
      final oneHourFromNow =
          DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String();

      await _apiService.createReminder(
        task.id,
        'Reminder: ${task.title}',
        oneHourFromNow,
      );

      print('--- CODEX REMINDER SUCCESS: Reminder created for task ---');
    } on SocketException {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
    } catch (e) {
      print('--- CODEX REMINDER TEST FAILED: $e ---');
    }
  }

  Future<void> _toggleTaskCompletion({
    required Task task,
    required bool newValue,
  }) async {
    final previousTasks = _tasks;
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _tasks = _tasks
          .map(
            (entry) =>
                entry.id == task.id
                    ? entry.copyWith(isCompleted: newValue)
                    : entry,
          )
          .toList(growable: false);
    });

    try {
      await _apiService.updateSubTaskCompletion(
        id: task.id,
        completed: newValue,
      );

      ApiService.notifyTaskMutation();

      if (!mounted) {
        return;
      }

      if (newValue && !task.isCompleted) {
        final earnedToken =
            ref.read(gachaControllerProvider.notifier).incrementTask();
        if (earnedToken) {
          messenger.showSnackBar(
            const SnackBar(content: Text('+1 Gacha Token Earned')),
          );
        }
      }
    } on SocketException {
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = previousTasks;
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = previousTasks;
      });

      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to update the task right now.')),
      );
    }
  }

  Future<bool> _handleTaskSwipe(DismissDirection direction, Task task) async {
    final messenger = ScaffoldMessenger.of(context);

    if (direction == DismissDirection.startToEnd) {
      try {
        await _apiService.updateSubTaskCompletion(id: task.id, completed: true);

        if (!mounted) {
          return false;
        }

        ApiService.notifyTaskMutation();

        if (!task.isCompleted) {
          final earnedToken =
              ref.read(gachaControllerProvider.notifier).incrementTask();
          if (earnedToken) {
            messenger.showSnackBar(
              const SnackBar(content: Text('+1 Gacha Token Earned')),
            );
          }
        }

        setState(() {
          _tasks = _tasks
              .where((entry) => entry.id != task.id)
              .toList(growable: false);
        });

        messenger.showSnackBar(
          SnackBar(content: Text('"${task.title}" marked completed.')),
        );
        return true;
      } on SocketException {
        if (!mounted) {
          return false;
        }

        messenger.showSnackBar(
          const SnackBar(
            content: Text('Cannot reach server right now. Please try again.'),
          ),
        );
        return false;
      } catch (error) {
        if (!mounted) {
          return false;
        }

        messenger.showSnackBar(
          SnackBar(content: Text('Unable to complete task: $error')),
        );
        return false;
      }
    }

    try {
      await _apiService.deleteTask(task.id);

      if (!mounted) {
        return false;
      }

      setState(() {
        _tasks = _tasks
            .where((entry) => entry.id != task.id)
            .toList(growable: false);
      });

      messenger.showSnackBar(
        SnackBar(content: Text('"${task.title}" deleted.')),
      );
      return true;
    } on SocketException {
      if (!mounted) {
        return false;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
      return false;
    } catch (error) {
      if (!mounted) {
        return false;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Unable to delete task: $error')),
      );
      return false;
    }
  }

  Future<void> _deleteAllTasks() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _apiService.deleteAllTasks();

      if (!mounted) {
        return;
      }

      await _fetchTasks();

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('All tasks deleted')),
      );
    } on SocketException {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Unable to delete tasks: $e')),
      );
    }
  }

  Future<void> _syncTasksToCalendar() async {
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isSyncingCalendar = true;
    });

    messenger.showSnackBar(const SnackBar(content: Text('Syncing...')));

    try {
      await _apiService.syncTasksToCalendar();

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('Tasks pushed to Google Calendar!')),
      );
    } on GoogleAccountNotLinkedException catch (error) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on SocketException {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Unable to sync calendar: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingCalendar = false;
        });
      }
    }
  }

  int get _remainingTasksCount =>
      _tasks.where((task) => !task.isCompleted).length;

  Color _priorityBg(String? band) {
    switch ((band ?? 'medium').trim().toLowerCase()) {
      case 'high':
        return const Color(0xFFFEE2E2);
      case 'low':
        return const Color(0xFFDCFCE7);
      default:
        return const Color(0xFFFFEDD5);
    }
  }

  Color _priorityFg(String? band) {
    switch ((band ?? 'medium').trim().toLowerCase()) {
      case 'high':
        return const Color(0xFFDC2626);
      case 'low':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFFEA580C);
    }
  }

  String _priorityLabel(String? band) {
    final normalized = (band ?? 'medium').trim().toLowerCase();
    switch (normalized) {
      case 'high':
        return 'High Priority';
      case 'low':
        return 'Low Priority';
      default:
        return 'Medium Priority';
    }
  }

  Future<void> _openCustomTaskScreen() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final created = await navigator.push<bool>(
      MaterialPageRoute(builder: (context) => const AddCustomTaskScreen()),
    );

    if (!mounted) {
      return;
    }

    if (created == true) {
      await _fetchTasks();

      if (!mounted) {
        return;
      }

      messenger.showSnackBar(const SnackBar(content: Text('Task created')));
    }
  }

  Widget _buildTaskChip({
    required String label,
    required Color background,
    required Color foreground,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(BuildContext context, Task task) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final shadow =
        isDark
            ? <BoxShadow>[]
            : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: shadow,
      ),
      child: Dismissible(
        key: Key(task.id),
        direction: DismissDirection.horizontal,
        background: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.shade600,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: const Icon(Icons.check_circle_rounded, color: Colors.white),
        ),
        secondaryBackground: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        confirmDismiss: (direction) => _handleTaskSwipe(direction, task),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                value: task.isCompleted,
                shape: const CircleBorder(),
                activeColor: const Color(0xFF8B5CF6),
                side: BorderSide(color: Colors.grey.shade400, width: 1.6),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (value) {
                  _toggleTaskCompletion(task: task, newValue: value ?? false);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTaskChip(
                          label: _priorityLabel(task.priorityBand),
                          background: _priorityBg(task.priorityBand),
                          foreground: _priorityFg(task.priorityBand),
                        ),
                        _buildTaskChip(
                          label:
                              task.estimatedMinutes != null &&
                                      task.estimatedMinutes! > 0
                                  ? '${task.estimatedMinutes} min'
                                  : 'Duration unknown',
                          background: const Color(0xFFF3F4F6),
                          foreground: Colors.grey.shade700,
                          icon: Icons.schedule_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => _createReminderForTask(task),
                onLongPress: _runReminderTest,
                icon: const Icon(Icons.notifications_none_rounded),
                color: const Color(0xFFF59E0B),
                tooltip: 'Set reminder',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remainingTasks = _remainingTasksCount;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF5F5F7);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final shadow =
        isDark
            ? <BoxShadow>[]
            : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ];

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _fetchTasks,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
            children: [
              Text(
                'Tasks',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$remainingTasks tasks remaining',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: subTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: shadow,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _openCustomTaskScreen,
                        icon: const Icon(Icons.add_task_rounded),
                        label: const Text('Add Custom Task'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF111827),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widget.enableVoiceCapture) ...[
                      VoiceCaptureWidget(
                        onTaskCreated: (response) {
                          unawaited(_handleVoiceTaskCreated(response));
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                _isSyncingCalendar
                                    ? null
                                    : _syncTasksToCalendar,
                            icon:
                                _isSyncingCalendar
                                    ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Icon(Icons.sync_rounded),
                            label: const Text('Sync to Calendar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF7C3AED),
                              backgroundColor: const Color(0xFFF3E8FF),
                              side: BorderSide.none,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _deleteAllTasks,
                            icon: const Icon(Icons.delete_sweep_rounded),
                            label: const Text('Delete All'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              backgroundColor: const Color(0xFFFEE2E2),
                              side: BorderSide.none,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_tasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No tasks yet.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: subTextColor),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _tasks.length,
                  itemBuilder: (context, index) {
                    return _buildTaskCard(context, _tasks[index]);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
