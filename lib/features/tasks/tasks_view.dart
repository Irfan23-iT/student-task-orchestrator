// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

import '../../models/task_model.dart';
import '../../services/api_service.dart';

class TasksView extends StatefulWidget {
  const TasksView({super.key});

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  final ApiService _apiService = ApiService();
  final _goalController = TextEditingController();

  List<Task> _tasks = const [];
  bool _isLoading = true;
  bool _isOrchestrating = false;

  @override
  void initState() {
    super.initState();
    _fetchTasks();
    _runCleanupVerification();
  }

  @override
  void dispose() {
    _goalController.dispose();
    super.dispose();
  }

  Future<void> _fetchTasks() async {
    try {
      final response = await _apiService.fetchTaskRows();
      final tasks = response.map(Task.fromJson).toList(growable: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
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
      await _apiService.fetchTaskRows();
      print('--- CODEX CLEANUP SUCCESS: Tasks fetched from API ---');
    } catch (e) {
      print('--- CODEX CLEANUP TEST FAILED: $e ---');
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

  Future<void> _createOrchestrationFromInput() async {
    final goal = _goalController.text.trim();
    if (goal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a goal for the AI planner first.')),
      );
      return;
    }

    setState(() {
      _isOrchestrating = true;
    });

    try {
      final response = await _apiService.createOrchestrationRun(goal);
      final runId = response['runId'] as String?;
      await _fetchTasks();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            runId == null
                ? 'AI orchestration submitted.'
                : 'AI orchestration submitted: $runId',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to start AI orchestration: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOrchestrating = false;
        });
      }
    }
  }

  Future<void> _deleteTask(Task task) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Single-task delete is not available from the backend for "${task.title}" yet.',
        ),
      ),
    );
    _fetchTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _goalController,
                    decoration: const InputDecoration(
                      labelText: 'AI task goal',
                      hintText: 'Break down my assignment into study tasks',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _isOrchestrating
                    ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                    : IconButton(
                      onPressed: _createOrchestrationFromInput,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      tooltip: 'Create AI orchestration run',
                    ),
              ],
            ),
          ),
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                      itemCount: _tasks.length,
                      itemBuilder: (context, index) {
                        final task = _tasks[index];
                        return Dismissible(
                          key: Key(task.id),
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: const Icon(
                              Icons.delete_rounded,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) => _deleteTask(task),
                          child: ListTile(
                            leading: Checkbox(
                              value: task.isCompleted,
                              onChanged: (value) {
                                _toggleTaskCompletion(
                                  task: task,
                                  newValue: value ?? false,
                                );
                              },
                            ),
                            title: Text(task.title),
                            trailing: IconButton(
                              onPressed: () => _createReminderForTask(task),
                              onLongPress: _runReminderTest,
                              icon: const Icon(Icons.notifications_none),
                              tooltip: 'Set reminder',
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
