// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/task_model.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';

class TasksView extends StatefulWidget {
  const TasksView({super.key});

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  final ApiService _apiService = ApiService();
  final TextEditingController _goalController = TextEditingController();
  final TextEditingController _manualTaskController = TextEditingController();

  List<Task> _tasks = const [];
  bool _isLoading = true;
  bool _isCreatingTask = false;
  bool _isGenerating = false;
  bool _isSyncingCalendar = false;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.initialize();
    _fetchTasks();
    _runCleanupVerification();
  }

  @override
  void dispose() {
    _goalController.dispose();
    _manualTaskController.dispose();
    super.dispose();
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
    try {
      final response = await _apiService.getTasks();
      final tasks = response.map(Task.fromJson).toList(growable: false);
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

  Future<void> _runCleanupVerification() async {
    try {
      print('--- CODEX CLEANUP TEST START ---');
      await _apiService.getTasks();
      print('--- CODEX CLEANUP SUCCESS: Tasks fetched from API ---');
    } catch (e) {
      print('--- CODEX CLEANUP TEST FAILED: $e ---');
    }
  }

  Future<void> _createManualTask() async {
    final title = _manualTaskController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a task title.')));
      return;
    }

    setState(() {
      _isCreatingTask = true;
    });

    try {
      await _apiService.createTask({
        'title': title,
        'priorityLevel': 'Medium',
        'status': 'Pending',
      });
      _manualTaskController.clear();
      await _fetchTasks();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Task created')));
    } on SocketException {
      _showNetworkErrorSnackBar();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to create task: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingTask = false;
        });
      }
    }
  }

  Future<void> _createReminderForTask(Task task) async {
    final oneHourFromNow =
        DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();

    try {
      await _apiService.createReminder(
        task.id,
        'Reminder: ${task.title}',
        oneHourFromNow,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder set for 1 hour from now')),
      );
    } on SocketException {
      _showNetworkErrorSnackBar();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to set reminder: $e')));
    }
  }

  Future<void> _runReminderTest() async {
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
      _showNetworkErrorSnackBar();
    } catch (e) {
      print('--- CODEX REMINDER TEST FAILED: $e ---');
    }
  }

  Future<void> _toggleTaskCompletion({
    required Task task,
    required bool newValue,
  }) async {
    final previousTasks = _tasks;

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
    } on SocketException {
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = previousTasks;
      });
      _showNetworkErrorSnackBar();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = previousTasks;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update the task right now.')),
      );
    }
  }

  Future<bool> _handleTaskSwipe(DismissDirection direction, Task task) async {
    if (direction == DismissDirection.startToEnd) {
      try {
        await _apiService.updateSubTaskCompletion(id: task.id, completed: true);

        if (!mounted) {
          return false;
        }

        setState(() {
          _tasks = _tasks
              .where((entry) => entry.id != task.id)
              .toList(growable: false);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${task.title}" marked completed.')),
        );
        return true;
      } on SocketException {
        _showNetworkErrorSnackBar();
        return false;
      } catch (error) {
        if (!mounted) {
          return false;
        }

        ScaffoldMessenger.of(context).showSnackBar(
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('"${task.title}" deleted.')));
      return true;
    } on SocketException {
      _showNetworkErrorSnackBar();
      return false;
    } catch (error) {
      if (!mounted) {
        return false;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to delete task: $error')));
      return false;
    }
  }

  Future<void> _deleteAllTasks() async {
    try {
      await _apiService.deleteAllTasks();
      await _fetchTasks();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('All tasks deleted')));
    } on SocketException {
      _showNetworkErrorSnackBar();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to delete tasks: $e')));
    }
  }

  Future<void> _generateTasksFromGoal() async {
    final goal = _goalController.text.trim();
    if (goal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a goal to generate tasks.')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      final generatedTasks = await _apiService.orchestrateGoal(goal);
      await _apiService.saveOrchestratedTasks(
        goal: goal,
        tasks: generatedTasks,
      );
      await _fetchTasks();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI-generated tasks saved successfully.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to generate tasks: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _syncTasksToCalendar() async {
    setState(() {
      _isSyncingCalendar = true;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Syncing...')));

    try {
      await _apiService.syncTasksToCalendar();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tasks pushed to Google Calendar!')),
      );
    } on GoogleAccountNotLinkedException catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } on SocketException {
      _showNetworkErrorSnackBar();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Dismissible(
        key: Key(task.id),
        direction: DismissDirection.horizontal,
        background: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.shade600,
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: const Icon(Icons.check_circle_rounded, color: Colors.white),
        ),
        secondaryBackground: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: const Icon(Icons.delete_rounded, color: Colors.white),
        ),
        confirmDismiss: (direction) => _handleTaskSwipe(direction, task),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                        color: Colors.black,
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _fetchTasks,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Text(
                'Tasks',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$remainingTasks tasks remaining',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualTaskController,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_isCreatingTask) {
                            _createManualTask();
                          }
                        },
                        decoration: const InputDecoration(
                          labelText: 'Task title',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filled(
                      onPressed: _isCreatingTask ? null : _createManualTask,
                      icon:
                          _isCreatingTask
                              ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Icon(Icons.add_rounded),
                      tooltip: 'Add task',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE9FE),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            color: Color(0xFF8B5CF6),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'AI Orchestrator',
                          style: Theme.of(
                            context,
                          ).textTheme.titleMedium?.copyWith(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: TextField(
                        controller: _goalController,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Enter a goal to generate tasks.',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            _isGenerating ? null : _generateTasksFromGoal,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child:
                            _isGenerating
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Text(
                                  'Generate',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _isSyncingCalendar ? null : _syncTasksToCalendar,
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
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
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
