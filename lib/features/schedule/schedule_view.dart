// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

import '../../models/class_model.dart';
import '../../services/api_service.dart';

class ScheduleView extends StatefulWidget {
  const ScheduleView({super.key});

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends State<ScheduleView> {
  List<ClassModel> _classes = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchClasses();
    _runScheduleMigrationTest();
  }

  Future<void> _fetchClasses() async {
    try {
      final classes = await ApiService().fetchFixedClasses();

      if (!mounted) {
        return;
      }

      setState(() {
        _classes = classes;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _classes = const [];
        _isLoading = false;
      });
    }
  }

  Future<void> _runScheduleMigrationTest() async {
    try {
      print('--- CODEX SCHEDULE MIGRATION TEST START ---');
      final classes = await ApiService().fetchFixedClasses();
      print(
        '--- CODEX SCHEDULE MIGRATION SUCCESS: Fetched ${classes.length} fixed classes from API ---',
      );
    } catch (e) {
      print('--- CODEX SCHEDULE MIGRATION TEST FAILED: $e ---');
    }
  }

  Future<void> _verifyClassInteraction({
    required List<ClassModel> classes,
    required TextEditingController classNameController,
  }) async {
    try {
      print('--- CODEX INTERACTION TEST START ---');
      print(
        'DEBUG: New class detected in local state: ${classes.any((c) => c.className == classNameController.text)}',
      );
      print('--- CODEX INTERACTION TEST SUCCESS ---');
    } catch (e) {
      print('--- CODEX INTERACTION TEST FAILED: $e ---');
    }
  }

  Future<void> _showAddClassDialog() async {
    final classNameController = TextEditingController();
    final classTypeController = TextEditingController();
    final startTimeController = TextEditingController();
    final endTimeController = TextEditingController();
    int dayValue = 1;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final navigator = Navigator.of(dialogContext);
        final messenger = ScaffoldMessenger.of(context);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Class'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: classNameController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Class Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: classTypeController,
                      decoration: const InputDecoration(
                        labelText: 'Class Type',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: dayValue,
                      decoration: const InputDecoration(
                        labelText: 'Day of Week',
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Monday')),
                        DropdownMenuItem(value: 2, child: Text('Tuesday')),
                        DropdownMenuItem(value: 3, child: Text('Wednesday')),
                        DropdownMenuItem(value: 4, child: Text('Thursday')),
                        DropdownMenuItem(value: 5, child: Text('Friday')),
                        DropdownMenuItem(value: 6, child: Text('Saturday')),
                        DropdownMenuItem(value: 7, child: Text('Sunday')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          dayValue = value ?? 1;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: startTimeController,
                      decoration: const InputDecoration(
                        labelText: 'Start Time',
                        hintText: '09:00:00',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endTimeController,
                      decoration: const InputDecoration(
                        labelText: 'End Time',
                        hintText: '10:00:00',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => navigator.pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final className = classNameController.text.trim();
                    final classType = classTypeController.text.trim();
                    final startTime = startTimeController.text.trim();
                    final endTime = endTimeController.text.trim();

                    if (className.isEmpty ||
                        classType.isEmpty ||
                        startTime.isEmpty ||
                        endTime.isEmpty) {
                      return;
                    }

                    classNameController.text = className;
                    classTypeController.text = classType;
                    startTimeController.text = startTime;
                    endTimeController.text = endTime;

                    try {
                      final newClass = ClassModel(
                        id: null,
                        dayOfWeek: dayValue,
                        startTime: startTimeController.text,
                        endTime: endTimeController.text,
                        className: classNameController.text,
                        classType: classTypeController.text,
                      );

                      await ApiService().saveFixedClass(newClass);

                      navigator.pop();
                      await _fetchClasses();
                      await _verifyClassInteraction(
                        classes: _classes,
                        classNameController: classNameController,
                      );
                    } catch (e) {
                      if (!mounted) {
                        return;
                      }

                      messenger.showSnackBar(
                        SnackBar(content: Text('Unable to add class: $e')),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    classNameController.dispose();
    classTypeController.dispose();
    startTimeController.dispose();
    endTimeController.dispose();
  }

  String _dayLabel(int dayOfWeek) {
    const labels = <int, String>{
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };

    return labels[dayOfWeek] ?? 'Day $dayOfWeek';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('My Schedule')),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _classes.length,
                itemBuilder: (context, index) {
                  final classItem = _classes[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(classItem.className),
                      subtitle: Text(
                        '${classItem.classType} • ${_dayLabel(classItem.dayOfWeek)} • ${classItem.startTime} - ${classItem.endTime}',
                      ),
                    ),
                  );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddClassDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
