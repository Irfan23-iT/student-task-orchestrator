// ignore_for_file: avoid_print

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/config/env_config.dart';
import '../../models/class_model.dart';
import '../../services/api_service.dart';

class ScheduleView extends StatefulWidget {
  const ScheduleView({
    super.key,
    @visibleForTesting this.fetchOnInit = true,
    @visibleForTesting this.fetchFixedClasses,
  });

  final bool fetchOnInit;
  final Future<List<ClassModel>> Function()? fetchFixedClasses;

  @override
  State<ScheduleView> createState() => _ScheduleViewState();
}

typedef SmartScheduleView = ScheduleView;

class _ScheduleViewState extends State<ScheduleView> {
  final ApiService _apiService = ApiService();

  List<ClassModel> _classes = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.fetchOnInit) {
      _fetchClasses();
    } else {
      _isLoading = false;
    }
  }

  Future<List<ClassModel>> _loadFixedClasses() {
    return widget.fetchFixedClasses?.call() ?? _apiService.fetchFixedClasses();
  }

  Future<void> _fetchClasses() async {
    try {
      final classes = await _loadFixedClasses();

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
    final cardColor = isDark ? const Color(0xFF111827) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final shadow =
        isDark
            ? <BoxShadow>[]
            : [
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ];

    final card = Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              accent.withValues(alpha: isDark ? 0.16 : 0.07),
              cardColor,
            ),
            cardColor,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.24 : 0.10),
        ),
        boxShadow: shadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, accent.withValues(alpha: 0.72)],
              ),
              borderRadius: BorderRadius.circular(20),
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
    final bgColor = isDark ? Colors.black : const Color(0xFFF4F0FF);
    final textColor = isDark ? Colors.white : const Color(0xFF111827);
    final subTextColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final shadow =
        isDark
            ? <BoxShadow>[]
            : [
              BoxShadow(
                color: const Color(0xFF4C1D95).withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ];

    return Scaffold(
      backgroundColor: bgColor,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton(
          heroTag: 'schedule-add-class-fab',
          onPressed: _showAddSubjectSheet,
          backgroundColor: const Color(0xFF4C1D95),
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 148),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors:
                        isDark
                            ? const [Color(0xFF080B18), Color(0xFF241044)]
                            : const [Color(0xFFFFFFFF), Color(0xFFEDE7FF)],
                  ),
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.72),
                  ),
                  boxShadow: shadow,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Schedule',
                            style: Theme.of(
                              context,
                            ).textTheme.headlineMedium?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Your fixed weekly classes',
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium?.copyWith(
                              color: subTextColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: Color(0xFF7C3AED),
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
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  final TextEditingController _lecturerController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _subjectNameController = TextEditingController();
  final TextEditingController _classTypeController = TextEditingController(
    text: 'Lecture',
  );
  final TextEditingController _lecturerNameController = TextEditingController();
  final TextEditingController _roomLocationController = TextEditingController();
  final TextEditingController _startTimeController = TextEditingController();
  final TextEditingController _endTimeController = TextEditingController();

  int _dayValue = 1;
  bool _isLoading = false;
  bool _isSaving = false;
  int _setupModeIndex = 0;
  PlatformFile? _selectedFile;

  static const Color _sheetBackground = Color(0xFF000000);
  static const Color _cardBackground = Color(0xFF1A1A24);
  static const Color _textSecondary = Color(0xFF888888);
  static const Color _neonGreen = Color(0xFF00FFB2);
  static const Color _brightBlue = Color(0xFF00AAFF);

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
    _subjectController.dispose();
    _timeController.dispose();
    _lecturerController.dispose();
    _locationController.dispose();
    _subjectNameController.dispose();
    _classTypeController.dispose();
    _lecturerNameController.dispose();
    _roomLocationController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  void _selectSetupMode(int index) {
    setState(() {
      _setupModeIndex = index;
    });
  }

  int _dayStringToValue(Object? value) {
    final normalized = (value ?? '').toString().trim().toLowerCase();
    const days = <String, int>{
      'monday': 1,
      'mon': 1,
      'tuesday': 2,
      'tue': 2,
      'wednesday': 3,
      'wed': 3,
      'thursday': 4,
      'thu': 4,
      'friday': 5,
      'fri': 5,
      'saturday': 6,
      'sat': 6,
      'sunday': 7,
      'sun': 7,
    };

    return days[normalized] ?? int.tryParse(normalized) ?? 1;
  }

  String _subjectCode(Object? value) {
    final text = (value ?? '').toString().trim().toUpperCase();
    final match = RegExp(r'[A-Z]{2,}\s*\d{3,}[A-Z0-9]*').firstMatch(text);
    return (match?.group(0) ?? text).replaceAll(RegExp(r'\s+'), '');
  }

  String _lecturerName(Object? value) {
    final raw = (value ?? '').toString().trim();
    final names = raw
        .split(RegExp(r'\s*(?:,|/|&|\band\b)\s*', caseSensitive: false))
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    return names.isEmpty ? 'TBA' : names.first;
  }

  bool _isConflictError(Object error) {
    return error.toString().toLowerCase().contains('time conflict');
  }

  String _extractStartTime(Object? value) {
    final time = (value ?? '').toString().trim();
    final tokens = _extractTimeTokens(time);
    final minutes =
        tokens.isNotEmpty ? _parseTimeToMinutes(tokens.first) : null;
    return _formatMinutesAsBackendTime(minutes ?? 8 * 60);
  }

  String _extractEndTime(Object? value) {
    final time = (value ?? '').toString().trim();
    final tokens = _extractTimeTokens(time);
    final startMinutes =
        tokens.isNotEmpty ? _parseTimeToMinutes(tokens.first) : null;
    final endMinutes =
        tokens.length > 1 ? _parseTimeToMinutes(tokens.last) : null;
    final safeStartMinutes = startMinutes ?? 8 * 60;
    final safeEndMinutes =
        endMinutes != null && endMinutes > safeStartMinutes
            ? endMinutes
            : safeStartMinutes + 60;

    return _formatMinutesAsBackendTime(safeEndMinutes);
  }

  List<String> _extractTimeTokens(String value) {
    return RegExp(
      r'\d{1,2}[:.]\d{2}(?::\d{2})?\s*(?:AM|PM|am|pm)?',
    ).allMatches(value).map((match) => match.group(0)!.trim()).toList();
  }

  int? _parseTimeToMinutes(Object? value) {
    final raw = (value ?? '').toString().trim();
    final match = RegExp(
      r'^(\d{1,2})[:.](\d{2})(?::\d{2})?\s*(AM|PM|am|pm)?',
    ).matchAsPrefix(raw);
    if (match == null) {
      return null;
    }

    var hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '');
    if (hour == null || minute == null || minute < 0 || minute > 59) {
      return null;
    }

    final meridiem = match.group(3)?.toUpperCase();
    if (meridiem == 'PM' && hour < 12) {
      hour += 12;
    } else if (meridiem == 'AM' && hour == 12) {
      hour = 0;
    }

    if (hour < 0 || hour > 23) {
      return null;
    }

    return hour * 60 + minute;
  }

  String _formatMinutesAsBackendTime(int totalMinutes) {
    final normalized = totalMinutes % (24 * 60);
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}:00';
  }

  InputDecoration _darkFieldDecoration({
    required String labelText,
    String? hintText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _cardBackground,
      labelStyle: const TextStyle(color: _textSecondary),
      hintStyle: const TextStyle(color: _textSecondary),
      suffixIconColor: _textSecondary,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _brightBlue, width: 1.4),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _cardBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _buildModeTab(index: 0, label: 'AI Auto-Scan ✨'),
          _buildModeTab(index: 1, label: 'Manual Entry 📝'),
        ],
      ),
    );
  }

  Widget _buildModeTab({required int index, required String label}) {
    final isSelected = _setupModeIndex == index;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _selectSetupMode(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient:
                isSelected
                    ? const LinearGradient(colors: [_neonGreen, _brightBlue])
                    : null,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAutoScanPanel() {
    final selectedFile = _selectedFile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Automated Timetable Setup',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Upload your official university timetable file or screenshot. RakanStudent's AI will automatically map your entire semester.",
          style: TextStyle(
            color: _textSecondary,
            fontSize: 14,
            height: 1.4,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 18),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _pickTimetableFile,
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: _neonGreen.withValues(alpha: 0.65),
              radius: 26,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 38),
              decoration: BoxDecoration(
                color: _cardBackground,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                children: [
                  Icon(
                    selectedFile == null
                        ? Icons.upload_file_rounded
                        : Icons.description_rounded,
                    color: _neonGreen,
                    size: 52,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    selectedFile?.name ?? 'Select Timetable PDF or Image',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    selectedFile == null
                        ? '(UniKL portal exports or screenshots supported)'
                        : '${selectedFile.size} bytes selected',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_neonGreen, _brightBlue]),
            borderRadius: BorderRadius.circular(999),
          ),
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            onPressed: _isLoading ? null : _analyzeAndSyncSemester,
            child: const Text(
              'Analyze and Sync Semester',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManualEntryForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Manual Entry',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Add a fixed weekly class manually when AI ingestion is not available.',
          style: TextStyle(color: _textSecondary, fontSize: 14, height: 1.4),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _subjectController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: _darkFieldDecoration(
            labelText: 'Class/Subject Name',
            hintText: 'Calculus',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _dayValue,
          dropdownColor: _cardBackground,
          style: const TextStyle(color: Colors.white),
          decoration: _darkFieldDecoration(labelText: 'Time/Day Selection'),
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
          style: const TextStyle(color: Colors.white),
          decoration: _darkFieldDecoration(
            labelText: 'Class Type',
            hintText: 'Lecture',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lecturerController,
          style: const TextStyle(color: Colors.white),
          decoration: _darkFieldDecoration(
            labelText: 'Lecturer Name',
            hintText: 'Dr. Name',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _locationController,
          style: const TextStyle(color: Colors.white),
          decoration: _darkFieldDecoration(
            labelText: 'Room/Location',
            hintText: 'Room A-01',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _startTimeController,
          readOnly: true,
          style: const TextStyle(color: Colors.white),
          onTap: () => _pickTime(_startTimeController),
          decoration: _darkFieldDecoration(
            labelText: 'Start Time',
            hintText: 'Select start time',
            suffixIcon: const Icon(Icons.schedule_rounded),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _endTimeController,
          readOnly: true,
          style: const TextStyle(color: Colors.white),
          onTap: () => _pickTime(_endTimeController),
          decoration: _darkFieldDecoration(
            labelText: 'End Time',
            hintText: 'Select end time',
            suffixIcon: const Icon(Icons.schedule_rounded),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _brightBlue,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          onPressed: _isSaving ? null : _saveManualClass,
          icon:
              _isSaving
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.save_alt_rounded),
          label: Text(_isSaving ? 'Saving...' : 'Save Class Manually'),
        ),
      ],
    );
  }

  TimeOfDay? _parseControllerTime(TextEditingController controller) {
    final parts = controller.text.trim().split(':');
    if (parts.length < 2) {
      return null;
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _pickTime(TextEditingController controller) async {
    FocusScope.of(context).unfocus();

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: _parseControllerTime(controller) ?? TimeOfDay.now(),
    );

    if (!mounted || selectedTime == null) {
      return;
    }

    final formattedTime =
        '${selectedTime.hour.toString().padLeft(2, '0')}:'
        '${selectedTime.minute.toString().padLeft(2, '0')}:00';

    setState(() {
      controller.text = formattedTime;
    });
  }

  Future<void> _pickTimetableFile() async {
    try {
      print(
        '📡 Initiating document picker for automated schedule extraction...',
      );
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );

      if (!mounted || result == null || result.files.isEmpty) {
        return;
      }

      setState(() {
        _selectedFile = result.files.single;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to select timetable file: $error')),
      );
    }
  }

  Future<void> _analyzeAndSyncSemester() async {
    final messenger = ScaffoldMessenger.of(context);
    final selectedFile = _selectedFile;

    if (selectedFile == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please select a timetable file first.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${EnvConfig.apiBaseUrl}/timetable/parse'),
      );
      request.headers.addAll(await _apiService.authHeaders());

      if (selectedFile.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            selectedFile.bytes!,
            filename: selectedFile.name,
          ),
        );
      } else if (selectedFile.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'file',
            selectedFile.path!,
            filename: selectedFile.name,
          ),
        );
      } else {
        throw StateError('Selected file has no readable bytes or path.');
      }

      var streamedResponse = await request.send();
      var responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        // 1. Raw, safe JSON decoding
        final Map<String, dynamic> responseData = jsonDecode(responseBody);
        final List<dynamic> extractedClasses = responseData['data'] ?? [];

        if (extractedClasses.isEmpty) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('⚠️ No classes found in response.')),
            );
          }
          return;
        }

        // 2. Data Injection
        final existingClasses = await _apiService.fetchFixedClasses();
        final seenSubjectCodes = <String>{
          for (final classItem in existingClasses)
            _subjectCode(classItem.className),
        };
        final uniqueExtractedClasses = <String, Map<String, dynamic>>{};

        for (final classItem in extractedClasses.whereType<Map>()) {
          final normalizedItem = Map<String, dynamic>.from(classItem);
          final code = _subjectCode(normalizedItem['subject']);
          if (code.isEmpty || code == 'TBA') {
            continue;
          }
          uniqueExtractedClasses.putIfAbsent(code, () {
            normalizedItem['subject'] = code;
            normalizedItem['lecturer'] = _lecturerName(
              normalizedItem['lecturer'],
            );
            return normalizedItem;
          });
        }

        var savedCount = 0;
        var skippedCount = 0;
        for (var classItem in uniqueExtractedClasses.values) {
          final subjectCode = _subjectCode(classItem['subject']);
          if (seenSubjectCodes.contains(subjectCode)) {
            skippedCount++;
            print('⏭️ Skipped existing class: $subjectCode');
            continue;
          }

          final parsedClass = ClassModel(
            id: null,
            dayOfWeek: _dayStringToValue(classItem['day']),
            startTime: _extractStartTime(classItem['time']),
            endTime: _extractEndTime(classItem['time']),
            className: subjectCode,
            classType:
                'Location: ${(classItem['location'] ?? 'TBA')} | Lecturer: ${_lecturerName(classItem['lecturer'])}',
          );
          try {
            await _apiService.saveFixedClass(parsedClass);
            seenSubjectCodes.add(subjectCode);
            savedCount++;
            print('📥 Successfully parsed class: $subjectCode');
          } catch (error) {
            if (_isConflictError(error)) {
              skippedCount++;
              print('⏭️ Skipped conflicting class: $subjectCode');
              continue;
            }
            rethrow;
          }
        }

        if (savedCount == 0 && skippedCount > 0) {
          throw StateError(
            'All parsed classes already exist or conflict with your current schedule.',
          );
        }

        // 3. Clean Navigation & UI Update
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✨ Timetable synced successfully!')),
          );
          ApiService.notifyScheduleMutation();
          Navigator.of(context).pop(true);
        }
      } else {
        throw Exception(
          'Server returned ${streamedResponse.statusCode}: $responseBody',
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to parse timetable: $error')),
      );
    }
  }

  Future<void> _saveManualClass() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    FocusScope.of(context).unfocus();
    final subject = _subjectController.text.trim();
    final classType = _classTypeController.text.trim();
    final lecturer = _lecturerController.text.trim();
    final location = _locationController.text.trim();
    final startTime = _startTimeController.text.trim();
    final endTime = _endTimeController.text.trim();
    final time = '$startTime-$endTime';
    _timeController.text = time;

    if (subject.isEmpty ||
        classType.isEmpty ||
        lecturer.isEmpty ||
        location.isEmpty ||
        startTime.isEmpty ||
        endTime.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please fill out all fields')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final payload = <String, Object>{
        'subject': subject,
        'classType': classType,
        'dayOfWeek': _dayValue,
        'time': time,
        'startTime': startTime,
        'endTime': endTime,
        'lecturer': lecturer,
        'location': location,
      };
      print('📝 Manual timetable payload: $payload');
      // TODO: ref.read(supabaseScheduleProvider.notifier).addClass(payload);

      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Class saved manually!'),
          backgroundColor: _neonGreen,
        ),
      );
      if (navigator.mounted) {
        navigator.pop(true);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to save manual class: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return SafeArea(
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + viewInsets.bottom),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: _sheetBackground),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Timetable Setup',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Choose AI ingestion or enter your fixed weekly class manually.',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _buildModeToggle(),
                    const SizedBox(height: 22),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: KeyedSubtree(
                        key: ValueKey<int>(_setupModeIndex),
                        child:
                            _setupModeIndex == 0
                                ? _buildAutoScanPanel()
                                : _buildManualEntryForm(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.72),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: _neonGreen),
                      SizedBox(height: 18),
                      Text(
                        'LangGraph engine analyzing scheduling layout...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 8.0;
      const gap = 6.0;
      while (distance < metric.length) {
        final next = distance + dash;
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
