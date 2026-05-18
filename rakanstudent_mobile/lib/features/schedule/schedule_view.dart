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
  final ApiService _apiService = ApiService();

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
      final classes = await _apiService.fetchFixedClasses();

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
      final classes = await _apiService.fetchFixedClasses();
      print(
        '--- CODEX SCHEDULE MIGRATION SUCCESS: Fetched ${classes.length} fixed classes from API ---',
      );
    } catch (e) {
      print('--- CODEX SCHEDULE MIGRATION TEST FAILED: $e ---');
    }
  }

  Future<void> _showAddSubjectSheet() async {
    final didSave = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const AddSubjectSheet(),
    );

    if (!mounted || didSave != true) {
      return;
    }

    await _fetchClasses();
  }

  Future<bool> _confirmDeleteClass(ClassModel classItem) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete class?'),
            content: Text(
              'Are you sure you want to delete ${classItem.className}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    return shouldDelete == true;
  }

  Future<bool> _deleteClass(ClassModel classItem) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final classId = classItem.id;
    if (classId == null || classId.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This class is missing a database id.')),
      );
      return false;
    }

    try {
      await _apiService.deleteClass(classId);
      if (!mounted || !navigator.mounted) {
        return false;
      }

      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Unable to delete class: $error')),
      );
      return false;
    }
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

  Color _accentColor(int index) {
    const colors = <Color>[
      Color(0xFFEC4899),
      Color(0xFF3B82F6),
      Color(0xFFF97316),
      Color(0xFF22C55E),
    ];

    return colors[index % colors.length];
  }

  Widget _buildChip({
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildClassCard(
    BuildContext context,
    ClassModel classItem,
    int index,
  ) {
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final accent = _accentColor(index);
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    final card = Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: shadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classItem.className,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildChip(
                      label: classItem.classType,
                      background: const Color(0xFFF3E8FF),
                      foreground: const Color(0xFF7C3AED),
                    ),
                    _buildChip(
                      label: _dayLabel(classItem.dayOfWeek),
                      background: const Color(0xFFF3F4F6),
                      foreground: Colors.grey.shade700,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Start ${classItem.startTime}  •  End ${classItem.endTime}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: subTextColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey(classItem.id ?? '${classItem.className}-$index'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        final shouldDelete = await _confirmDeleteClass(classItem);
        if (!shouldDelete) {
          return false;
        }

        return _deleteClass(classItem);
      },
      onDismissed: (_) {
        final classId = classItem.id;
        setState(() {
          _classes = _classes
              .where((entry) => entry.id != classId)
              .toList(growable: false);
        });

        messenger.showSnackBar(
          SnackBar(content: Text('${classItem.className} deleted.')),
        );
      },
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.error,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(
          Icons.delete_rounded,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      child: card,
    );
  }

  @override
  Widget build(BuildContext context) {
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
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton(
          onPressed: _showAddSubjectSheet,
          backgroundColor: const Color(0xFF111827),
          foregroundColor: Colors.white,
          elevation: 8,
          shape: const CircleBorder(),
          child: const Icon(Icons.add, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _fetchClasses,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 148),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: shadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Schedule',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Your fixed weekly classes',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: subTextColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_classes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No fixed classes yet.',
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
                  padding: const EdgeInsets.only(bottom: 100, top: 16),
                  itemCount: _classes.length,
                  itemBuilder: (context, index) {
                    final classItem = _classes[index];
                    return _buildClassCard(context, classItem, index);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddSubjectSheet extends StatefulWidget {
  const AddSubjectSheet({super.key});

  @override
  State<AddSubjectSheet> createState() => _AddSubjectSheetState();
}

class _AddSubjectSheetState extends State<AddSubjectSheet> {
  final ApiService _apiService = ApiService();
  final TextEditingController _subjectNameController = TextEditingController();
  final TextEditingController _classTypeController = TextEditingController(
    text: 'Lecture',
  );
  final TextEditingController _startTimeController = TextEditingController();
  final TextEditingController _endTimeController = TextEditingController();

  int _dayValue = 1;
  bool _isSaving = false;

  static const Map<int, String> _dayLabels = <int, String>{
    1: 'Monday',
    2: 'Tuesday',
    3: 'Wednesday',
    4: 'Thursday',
    5: 'Friday',
    6: 'Saturday',
    7: 'Sunday',
  };

  @override
  void dispose() {
    _subjectNameController.dispose();
    _classTypeController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  Future<void> _saveSubject() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    FocusScope.of(context).unfocus();
    final subjectName = _subjectNameController.text.trim();
    final classType = _classTypeController.text.trim();
    final startTime = _startTimeController.text.trim();
    final endTime = _endTimeController.text.trim();

    if (subjectName.isEmpty ||
        classType.isEmpty ||
        startTime.isEmpty ||
        endTime.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Fill in all subject details first.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    var didSave = false;
    try {
      final newClass = ClassModel(
        id: null,
        dayOfWeek: _dayValue,
        startTime: startTime,
        endTime: endTime,
        className: subjectName,
        classType: classType,
      );

      await _apiService.saveFixedClass(newClass);
      didSave = true;

      if (!mounted) {
        return;
      }

      navigator.pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Unable to add subject: $error')),
      );
    } finally {
      if (mounted && _isSaving && !didSave) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
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

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + viewInsets.bottom),
        child: DecoratedBox(
          decoration: BoxDecoration(color: bgColor),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add Subject',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Create a fixed weekly class',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: subTextColor),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: shadow,
                  ),
                  child: Column(
                    children: [
                      TextField(
                        controller: _subjectNameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Subject Name',
                          hintText: 'Calculus',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: _dayValue,
                        decoration: const InputDecoration(
                          labelText: 'Day of Week',
                        ),
                        items: _dayLabels.entries
                            .map(
                              (entry) => DropdownMenuItem<int>(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          setState(() {
                            _dayValue = value ?? 1;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _classTypeController,
                        decoration: const InputDecoration(
                          labelText: 'Class Type',
                          hintText: 'Lecture',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _startTimeController,
                        decoration: const InputDecoration(
                          labelText: 'Start Time',
                          hintText: '09:00:00',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _endTimeController,
                        decoration: const InputDecoration(
                          labelText: 'End Time',
                          hintText: '10:00:00',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _isSaving ? null : _saveSubject,
                        icon:
                            _isSaving
                                ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.save_alt_rounded),
                        label: Text(_isSaving ? 'Saving...' : 'Save Subject'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
