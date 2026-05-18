import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/supabase_client.dart';
import '../models/class_schedule_model.dart';
import '../models/task_model.dart';
import '../services/api_service.dart';

class CalendarView extends StatefulWidget {
  const CalendarView({
    super.key,
    @visibleForTesting this.initialTasks = const [],
    @visibleForTesting this.initialClasses = const [],
    @visibleForTesting this.fetchOnInit = true,
  });

  final List<Task> initialTasks;
  final List<ClassSchedule> initialClasses;
  final bool fetchOnInit;

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  static const int _maxImageBytes = 1024 * 1024;

  final ApiService _apiService = ApiService();
  final ImagePicker _imagePicker = ImagePicker();

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  Map<DateTime, List<Object>> _eventsByDay = const {};
  List<ClassSchedule> _classSchedules = const [];
  bool _isLoading = true;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    ApiService.taskMutationNotifier.addListener(_handleTaskMutation);
    if (widget.initialClasses.isNotEmpty) {
      _classSchedules = widget.initialClasses;
    }
    if (widget.initialTasks.isNotEmpty || widget.initialClasses.isNotEmpty) {
      _eventsByDay = _groupCalendarEvents(
        tasks: widget.initialTasks,
        classes: _classSchedules,
        startDate: _monthStart(_focusedDay),
        endDate: _monthEnd(_focusedDay),
      );
      _isLoading = false;
    }
    if (widget.fetchOnInit) {
      _fetchVisibleMonth();
    }
  }

  @override
  void dispose() {
    ApiService.taskMutationNotifier.removeListener(_handleTaskMutation);
    super.dispose();
  }

  void _handleTaskMutation() {
    if (mounted) {
      _fetchVisibleMonth(showLoading: false);
    }
  }

  DateTime _dayKey(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  DateTime _monthStart(DateTime value) => DateTime(value.year, value.month);

  DateTime _monthEnd(DateTime value) {
    final nextMonth = DateTime(value.year, value.month + 1);
    return nextMonth.subtract(const Duration(milliseconds: 1));
  }

  List<Object> _eventsForDay(DateTime day) =>
      _eventsByDay[_dayKey(day)] ?? const [];

  Map<DateTime, List<Object>> _groupCalendarEvents({
    required List<Task> tasks,
    required List<ClassSchedule> classes,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    final groupedEvents = <DateTime, List<Object>>{};
    final dedupedTasks = _dedupeTasks(tasks);
    final dedupedClasses = _dedupeClassSchedules(classes);

    for (final task in dedupedTasks) {
      final dueDate = task.dueDate;
      if (dueDate == null) {
        continue;
      }

      final key = _dayKey(dueDate);
      groupedEvents.putIfAbsent(key, () => <Object>[]).add(task);
    }

    for (
      var day = _dayKey(startDate);
      !day.isAfter(_dayKey(endDate));
      day = day.add(const Duration(days: 1))
    ) {
      for (final classSchedule in dedupedClasses) {
        if (classSchedule.dayOfWeek == day.weekday) {
          groupedEvents.putIfAbsent(day, () => <Object>[]).add(classSchedule);
        }
      }
    }

    return groupedEvents;
  }

  List<Task> _dedupeTasks(List<Task> fetchedTasks) {
    final uniqueTasks = <String, Task>{};

    for (final task in fetchedTasks) {
      final normalizedTitle = task.title.trim().toLowerCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      final dueDate = task.dueDate;
      final dateKey =
          dueDate == null
              ? 'no-date'
              : '${dueDate.toLocal().year}-${dueDate.toLocal().month}-${dueDate.toLocal().day}';
      final key = '$normalizedTitle|$dateKey';

      uniqueTasks.putIfAbsent(key, () => task);
    }

    return uniqueTasks.values.toList(growable: false);
  }

  List<ClassSchedule> _dedupeClassSchedules(
    List<ClassSchedule> fetchedClasses,
  ) {
    final uniqueClasses = <String, ClassSchedule>{};

    for (final classSchedule in fetchedClasses) {
      final normalizedId = classSchedule.id.trim();
      final fallbackKey = [
        classSchedule.courseName.trim().toLowerCase(),
        classSchedule.dayOfWeek.toString(),
        classSchedule.startTime.trim(),
        classSchedule.endTime.trim(),
      ].join('|');
      final key = normalizedId.isEmpty ? fallbackKey : normalizedId;

      uniqueClasses[key] = classSchedule;
    }

    return uniqueClasses.values.toList(growable: false);
  }

  Future<void> _fetchVisibleMonth({bool showLoading = true}) async {
    if (mounted) {
      setState(() {
        _eventsByDay = const {};
        _classSchedules = const [];
        if (showLoading) {
          _isLoading = true;
        }
      });
    }

    try {
      final startDate = _monthStart(_focusedDay);
      final endDate = _monthEnd(_focusedDay);
      final responses = await Future.wait([
        _apiService.getTasks(startDate: startDate, endDate: endDate),
        _apiService.fetchPrimaryTasks(startDate: startDate, endDate: endDate),
        _apiService.fetchTaskRows(),
      ]);
      final classRows =
          await AppSupabaseClient.instance.from('fixed_classes').select();
      final classSchedules = _dedupeClassSchedules(
        classRows.map(ClassSchedule.fromJson).toList(growable: false),
      );
      final tasks = _dedupeTasks(
        responses
            .expand((response) => response)
            .map(Task.fromJson)
            .where((task) {
              return task.dueDate != null;
            })
            .toList(growable: false),
      );
      final groupedEvents = _groupCalendarEvents(
        tasks: tasks,
        classes: classSchedules,
        startDate: startDate,
        endDate: endDate,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _classSchedules = classSchedules;
        _eventsByDay = groupedEvents;
        _isLoading = false;
      });
    } on SocketException {
      if (!mounted) {
        return;
      }

      setState(() {
        _eventsByDay = const {};
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot reach server right now. Please try again.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _eventsByDay = const {};
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to load calendar tasks: $error')),
      );
    }
  }

  String _priorityLabel(String? priority) {
    final normalized = (priority ?? 'Medium').trim().toLowerCase();
    switch (normalized) {
      case 'high':
        return 'High';
      case 'low':
        return 'Low';
      default:
        return 'Medium';
    }
  }

  Color _priorityColor(String? priority) {
    final normalized = (priority ?? 'medium').trim().toLowerCase();
    switch (normalized) {
      case 'high':
        return const Color(0xFFDC2626);
      case 'low':
        return const Color(0xFF16A34A);
      default:
        return const Color(0xFFEA580C);
    }
  }

  Color _colorFromHex(String colorHex) {
    final normalized = colorHex.replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) {
      return const Color(0xFF2563EB);
    }
    return Color(0xFF000000 | parsed);
  }

  String _classTimeRange(ClassSchedule classSchedule) {
    return '${classSchedule.startTime} - ${classSchedule.endTime}';
  }

  Widget _buildTaskTile(Task task) {
    final dueDate = task.dueDate;
    final timeLabel =
        dueDate == null ? null : DateFormat('h:mm a').format(dueDate.toLocal());
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

    return Container(
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
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: _priorityColor(task.priorityBand),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    _priorityLabel(task.priorityBand),
                    if (timeLabel != null) timeLabel,
                  ].join(' | '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: subTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassTile(ClassSchedule classSchedule) {
    final color = _colorFromHex(classSchedule.colorHex);
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: isDark ? 0.14 : 0.08),
          cardColor,
        ),
        border: Border.all(color: color.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(24),
        boxShadow: shadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classSchedule.courseName,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    'Class',
                    if (classSchedule.classType != null)
                      classSchedule.classType!,
                    _classTimeRange(classSchedule),
                  ].join(' | '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: subTextColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarEventTile(Object event) {
    if (event is ClassSchedule) {
      return _buildClassTile(event);
    }

    if (event is Task) {
      return _buildTaskTile(event);
    }

    return const SizedBox.shrink();
  }

  Color _markerColor(List<Object> events) {
    for (final event in events) {
      if (event is ClassSchedule) {
        return _colorFromHex(event.colorHex);
      }
    }

    return const Color(0xFF8B5CF6);
  }

  String _mimeTypeForImage(XFile image) {
    final explicitMimeType = image.mimeType;
    if (explicitMimeType != null && explicitMimeType.startsWith('image/')) {
      return explicitMimeType;
    }

    final path = image.path.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.heic')) return 'image/heic';
    if (path.endsWith('.heif')) return 'image/heif';
    return 'image/jpeg';
  }

  void _showScanningDialog(BuildContext dialogContext) {
    showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder:
          (context) => const AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(width: 18),
                Expanded(child: Text('Scanning & Orchestrating...')),
              ],
            ),
          ),
    );
  }

  void _dismissScanningDialog(NavigatorState navigator) {
    navigator.pop();
  }

  Future<void> _refreshCalendarAfterScan() async {
    await _fetchVisibleMonth(showLoading: false);
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _scanScheduleImage() async {
    if (_isScanning) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    setState(() {
      _isScanning = true;
    });

    var dialogOpen = false;
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 55,
        requestFullMetadata: false,
      );

      if (image == null) {
        return;
      }

      final bytes = await image.readAsBytes();
      if (bytes.lengthInBytes > _maxImageBytes) {
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Image is still over 1 MB. Please retake it closer.'),
          ),
        );
        return;
      }

      if (!mounted) return;
      _showScanningDialog(rootNavigator.context);
      dialogOpen = true;

      final response = await _apiService.scanImageForTasks(
        imageBase64: base64Encode(bytes),
        mimeType: _mimeTypeForImage(image),
      );
      final createdItems = response['created'] as List<dynamic>? ?? const [];
      if (createdItems.isNotEmpty) {
        ApiService.notifyTaskMutation();
      }

      if (!mounted) return;
      if (dialogOpen) {
        _dismissScanningDialog(rootNavigator);
        dialogOpen = false;
      }
      await _refreshCalendarAfterScan();
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            createdItems.isEmpty
                ? 'No academic tasks found in that image.'
                : 'Added ${createdItems.length} task group${createdItems.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Unable to scan image: $error')),
      );
    } finally {
      if (dialogOpen && mounted) {
        _dismissScanningDialog(rootNavigator);
      }
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedEvents = _eventsForDay(_selectedDay);
    final selectedLabel = DateFormat('EEE, MMM d').format(_selectedDay);
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
          onRefresh: () => _fetchVisibleMonth(showLoading: false),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
            children: [
              Text(
                'Calendar',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tasks by due date',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: subTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: shadow,
                ),
                child: Stack(
                  children: [
                    TableCalendar<Object>(
                      firstDay: DateTime.utc(2020),
                      lastDay: DateTime.utc(2035, 12, 31),
                      focusedDay: _focusedDay,
                      selectedDayPredicate:
                          (day) => isSameDay(day, _selectedDay),
                      eventLoader: _eventsForDay,
                      calendarFormat: CalendarFormat.month,
                      availableCalendarFormats: const {
                        CalendarFormat.month: 'Month',
                      },
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                      ),
                      calendarStyle: CalendarStyle(
                        defaultTextStyle: TextStyle(color: textColor),
                        weekendTextStyle: TextStyle(color: textColor),
                        outsideTextStyle: TextStyle(
                          color: subTextColor ?? Colors.grey,
                        ),
                        todayDecoration: const BoxDecoration(
                          color: Color(0xFFEDE9FE),
                          shape: BoxShape.circle,
                        ),
                        todayTextStyle: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w800,
                        ),
                        selectedDecoration: const BoxDecoration(
                          color: Color(0xFF111827),
                          shape: BoxShape.circle,
                        ),
                        selectedTextStyle: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      calendarBuilders: CalendarBuilders<Object>(
                        markerBuilder: (context, day, tasks) {
                          if (tasks.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Positioned(
                            bottom: 7,
                            child: Container(
                              key: ValueKey<String>(
                                'calendar-marker-${day.year}-${day.month}-${day.day}',
                              ),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: _markerColor(tasks),
                                shape: BoxShape.circle,
                              ),
                            ),
                          );
                        },
                      ),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _selectedDay = selectedDay;
                          _focusedDay = focusedDay;
                        });
                      },
                      onPageChanged: (focusedDay) {
                        setState(() {
                          _focusedDay = focusedDay;
                          _selectedDay = focusedDay;
                        });
                        _fetchVisibleMonth();
                      },
                    ),
                    if (_isLoading)
                      const Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x55FFFFFF),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                selectedLabel,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              if (selectedEvents.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No tasks or classes on this date.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: subTextColor),
                  ),
                )
              else
                ...selectedEvents.map(_buildCalendarEventTile),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: FloatingActionButton(
          heroTag: 'calendar-scan-schedule-fab',
          tooltip: 'Scan schedule image',
          onPressed: _isScanning ? null : _scanScheduleImage,
          child:
              _isScanning
                  ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  )
                  : const Icon(Icons.camera_alt_rounded),
        ),
      ),
    );
  }
}
