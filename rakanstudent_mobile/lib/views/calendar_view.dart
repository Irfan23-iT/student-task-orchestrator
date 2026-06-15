import 'dart:io';

import 'package:flutter/material.dart';
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

  static bool _bypassCalendarFetchForTests = false;

  @visibleForTesting
  static void enableCalendarFetchBypassForTests() {
    _bypassCalendarFetchForTests = true;
  }

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  final ApiService _apiService = ApiService();

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  Map<DateTime, List<Object>> _eventsByDay = const {};
  List<ClassSchedule> _classSchedules = const [];
  bool _isLoading = true;

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

    if (CalendarView._bypassCalendarFetchForTests) {
      if (!mounted) {
        return;
      }

      final startDate = _monthStart(_focusedDay);
      final endDate = _monthEnd(_focusedDay);
      final groupedEvents = _groupCalendarEvents(
        tasks: widget.initialTasks,
        classes: widget.initialClasses,
        startDate: startDate,
        endDate: endDate,
      );

      setState(() {
        _classSchedules = widget.initialClasses;
        _eventsByDay = groupedEvents;
        _isLoading = false;
      });
      return;
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = colorScheme.surface;
    final textColor = colorScheme.onSurface;
    final subTextColor = colorScheme.onSurfaceVariant;
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = colorScheme.surface;
    final textColor = colorScheme.onSurface;
    final subTextColor = colorScheme.onSurfaceVariant;
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
                if (classSchedule.location != null &&
                    classSchedule.location!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '\u{1F4CD} ${classSchedule.location}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: subTextColor,
                    ),
                  ),
                ],
                if (classSchedule.lecturer != null &&
                    classSchedule.lecturer!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '\u{1F464} ${classSchedule.lecturer}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: subTextColor,
                    ),
                  ),
                ],
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

    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final selectedEvents = _eventsForDay(_selectedDay);
    final selectedLabel = DateFormat('EEE, MMM d').format(_selectedDay);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = colorScheme.surface;
    final textColor = colorScheme.onSurface;
    final subTextColor = colorScheme.onSurfaceVariant;
    final shadow =
        isDark
            ? <BoxShadow>[]
            : [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 14),
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
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 140),
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [colorScheme.primary, colorScheme.secondary],
                  ),
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(
                    color: colorScheme.outline,
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
                            'Calendar',
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
                            'Tasks with due dates appear here automatically',
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
                        color: colorScheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(
                        Icons.event_available_rounded,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
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
                          color: subTextColor,
                        ),
                        todayDecoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        todayTextStyle: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                        selectedDecoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        selectedTextStyle: TextStyle(
                          color: colorScheme.onPrimary,
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
    );
  }
}
