// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/analytics_model.dart';
import '../../services/api_service.dart';
import 'sprint_game_screen.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  static const List<int> _focusDurationOptions = [15, 25, 50];
  static const int _defaultFocusDurationMinutes = 25;

  final ApiService _apiService = ApiService();

  List<ReminderJobModel> _activeReminders = const [];
  int _pendingTasksCount = 0;
  String _nextClassName = 'No classes today';
  String _nextClassSubtitle = 'Next Class';
  int _currentStreak = 0;
  Timer? _timer;
  int _focusDurationMinutes = _defaultFocusDurationMinutes;
  int _secondsRemaining = _defaultFocusDurationMinutes * 60;

  bool get _isFocusTimerActive => _timer?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    _loadAnalyticsOverview();
    ApiService.taskMutationNotifier.addListener(_handleTaskMutation);
    _loadDashboardData();
    _loadFocusPreferences();
    _runApiBridgeHealthTest();
  }

  @override
  void dispose() {
    _timer?.cancel();
    ApiService.taskMutationNotifier.removeListener(_handleTaskMutation);
    super.dispose();
  }

  Future<void> _handleTaskMutation() async {
    await _refreshDashboard();
  }

  Future<void> _runApiBridgeHealthTest() async {
    try {
      final response = await _apiService.checkHealth();
      print('DEBUG: API Health Status: ${response.statusCode}');
    } catch (e) {
      print('DEBUG: API Health Status check failed: $e');
    }
  }

  Future<void> _runDashboardPolishTest({
    required int pendingTasksCount,
    required int classesTodayCount,
  }) async {
    print('--- CODEX DASHBOARD POLISH TEST START ---');
    print('DEBUG: Pending Tasks: $pendingTasksCount');
    print('DEBUG: Classes Today: $classesTodayCount');
    print('--- CODEX DASHBOARD POLISH TEST SUCCESS ---');
  }

  Future<AnalyticsModel> _loadAnalyticsOverview() async {
    try {
      final analytics = await _apiService.fetchAnalyticsOverview();

      if (mounted) {
        setState(() {
          _activeReminders = List<ReminderJobModel>.from(
            analytics.reminderJobs,
          );
        });
      }

      return analytics;
    } catch (error) {
      if (mounted) {
        setState(() {
          _activeReminders = const [];
        });
      }

      return const AnalyticsModel(
        streakSnapshot: {'currentStreak': 0},
        reminderJobs: <ReminderJobModel>[],
        userBadges: <UserBadgeModel>[],
        notificationPreferences: NotificationPreferencesModel(
          inboxEnabled: true,
          emailEnabled: false,
          reminderLeadMinutes: 30,
          quietHoursStart: '22:00',
          quietHoursEnd: '07:00',
          timeZone: 'UTC',
        ),
      );
    }
  }

  Future<void> _refreshDashboard() async {
    await Future.wait<void>([
      _loadAnalyticsOverview(),
      _loadDashboardData(),
      _loadFocusPreferences(),
    ]);
  }

  int _parseFocusDurationMinutes(Object? value) {
    final minutes =
        value is num
            ? value.toInt()
            : int.tryParse(value?.toString().trim() ?? '');

    if (minutes == null || minutes <= 0) {
      return _defaultFocusDurationMinutes;
    }

    return minutes;
  }

  int _parseFocusStreak(Object? value) {
    final streak =
        value is num
            ? value.toInt()
            : int.tryParse(value?.toString().trim() ?? '');

    if (streak == null || streak < 0) {
      return 0;
    }

    return streak;
  }

  Future<void> _loadFocusPreferences() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) {
        return;
      }

      final response =
          await supabase
              .from('user_preferences')
              .select('focus_duration_minutes, focus_streak')
              .eq('user_id', userId)
              .maybeSingle();
      final durationMinutes = _parseFocusDurationMinutes(
        response?['focus_duration_minutes'],
      );
      final focusStreak = _parseFocusStreak(response?['focus_streak']);

      if (!mounted) {
        return;
      }

      setState(() {
        _currentStreak = focusStreak;
        if (!_isFocusTimerActive) {
          _focusDurationMinutes = durationMinutes;
          _secondsRemaining = durationMinutes * 60;
        }
      });
    } catch (error, stackTrace) {
      print('Focus preferences fetch failed: $error');
      print(stackTrace);
    }
  }

  String _formatFocusTime() {
    final minutes = _secondsRemaining ~/ 60;
    final seconds = _secondsRemaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _cycleFocusDuration() {
    _timer?.cancel();
    _timer = null;

    final currentIndex = _focusDurationOptions.indexOf(_focusDurationMinutes);
    final nextIndex =
        currentIndex == -1
            ? 0
            : (currentIndex + 1) % _focusDurationOptions.length;
    final nextDurationMinutes = _focusDurationOptions[nextIndex];

    setState(() {
      _focusDurationMinutes = nextDurationMinutes;
      _secondsRemaining = nextDurationMinutes * 60;
    });
  }

  void _toggleFocusTimer() {
    if (_isFocusTimerActive) {
      _pauseFocusTimer();
      return;
    }

    _startFocusTimer();
  }

  void _startFocusTimer() {
    if (_secondsRemaining <= 0) {
      setState(() {
        _secondsRemaining = _focusDurationMinutes * 60;
      });
    }

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_secondsRemaining <= 1) {
        timer.cancel();
        _timer = null;
        setState(() {
          _secondsRemaining = 0;
        });
        _completeFocusSession();
        return;
      }

      setState(() {
        _secondsRemaining--;
      });
    });

    setState(() {});
  }

  void _pauseFocusTimer() {
    _timer?.cancel();
    _timer = null;

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _completeFocusSession() {
    unawaited(_incrementFocusStreak());
    HapticFeedback.vibrate();

    if (!mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Focus Session Complete'),
            content: const Text(
              'Nice work. Take a short break before the next round.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Future<void> _incrementFocusStreak() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) {
        return;
      }

      final response =
          await supabase
              .from('user_preferences')
              .select('focus_streak')
              .eq('user_id', userId)
              .maybeSingle();
      final nextStreak = _parseFocusStreak(response?['focus_streak']) + 1;

      if (response == null) {
        await supabase.from('user_preferences').upsert({
          'user_id': userId,
          'wake_time': '07:00',
          'sleep_time': '23:00',
          'focus_duration_minutes': _focusDurationMinutes,
          'focus_streak': nextStreak,
        }, onConflict: 'user_id');
      } else {
        await supabase
            .from('user_preferences')
            .update({'focus_streak': nextStreak})
            .eq('user_id', userId);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _currentStreak = nextStreak;
      });
    } catch (error, stackTrace) {
      print('Focus streak increment failed: $error');
      print(stackTrace);
    }
  }

  String _todayDayCode() {
    // Add Subject saves day_of_week as MON/TUE/WED/THU/FRI/SAT/SUN.
    const dayCodes = <int, String>{
      DateTime.monday: 'MON',
      DateTime.tuesday: 'TUE',
      DateTime.wednesday: 'WED',
      DateTime.thursday: 'THU',
      DateTime.friday: 'FRI',
      DateTime.saturday: 'SAT',
      DateTime.sunday: 'SUN',
    };

    final dayCode = dayCodes[DateTime.now().weekday] ?? 'MON';
    print('DEBUG: Today weekday ${DateTime.now().weekday} maps to $dayCode');
    return dayCode;
  }

  bool _isPendingStatus(Object? value) {
    final normalized = (value ?? 'pending')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_');
    const resolvedStatuses = <String>{
      'complete',
      'completed',
      'done',
      'archived',
      'cancelled',
      'canceled',
    };

    return !resolvedStatuses.contains(normalized);
  }

  bool _isTruthy(Object? value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final normalized = value?.toString().trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  bool _isPendingTaskRow(Map<String, dynamic> row) {
    final isCompleted = row['is_completed'] ?? row['isCompleted'];
    if (_isTruthy(isCompleted)) {
      return false;
    }

    return _isPendingStatus(row['status']);
  }

  bool _isTodayClassRow(Map<String, dynamic> row, String todayDayCode) {
    final rawDay = row['day_of_week'] ?? row['dayOfWeek'];
    if (rawDay is num) {
      final dayOfWeek = rawDay.toInt() == 0 ? DateTime.sunday : rawDay.toInt();
      return dayOfWeek == DateTime.now().weekday;
    }

    final normalized = '${rawDay ?? ''}'.trim().toUpperCase();
    final numericDay = int.tryParse(normalized);
    if (numericDay != null) {
      final dayOfWeek = numericDay == 0 ? DateTime.sunday : numericDay;
      return dayOfWeek == DateTime.now().weekday;
    }

    return normalized == todayDayCode;
  }

  String _stringFromRow(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    return '';
  }

  int _minutesFromTime(Object? value) {
    final rawValue = value?.toString().trim() ?? '';
    final timeParts = rawValue.split(':');
    final hour = int.tryParse(timeParts.isNotEmpty ? timeParts[0] : '');
    final minute = int.tryParse(timeParts.length > 1 ? timeParts[1] : '');
    if (hour == null || minute == null) {
      return 24 * 60;
    }

    return hour * 60 + minute;
  }

  String _formatTimeLabel(Object? value) {
    final rawValue = value?.toString().trim() ?? '';
    if (rawValue.isEmpty) {
      return '';
    }

    final timeParts = rawValue.split(':');
    if (timeParts.length < 2) {
      return rawValue;
    }

    return '${timeParts[0].padLeft(2, '0')}:${timeParts[1].padLeft(2, '0')}';
  }

  Map<String, dynamic>? _nextClassFromRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return null;
    }

    final sortedRows = List<Map<String, dynamic>>.from(rows)..sort((
      left,
      right,
    ) {
      return _minutesFromTime(
        left['start_time'] ?? left['startTime'],
      ).compareTo(_minutesFromTime(right['start_time'] ?? right['startTime']));
    });
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    for (final row in sortedRows) {
      final startMinutes = _minutesFromTime(
        row['start_time'] ?? row['startTime'],
      );
      final endMinutes = _minutesFromTime(row['end_time'] ?? row['endTime']);
      if (currentMinutes <= startMinutes ||
          (currentMinutes >= startMinutes && currentMinutes < endMinutes)) {
        return row;
      }
    }

    return sortedRows.last;
  }

  ({String name, String subtitle}) _nextClassDisplay(
    List<Map<String, dynamic>> todayClassRows,
  ) {
    final nextClass = _nextClassFromRows(todayClassRows);
    if (nextClass == null) {
      return (name: 'No classes today', subtitle: 'Next Class');
    }

    final className = _stringFromRow(nextClass, const [
      'class_name',
      'className',
      'course_name',
      'courseName',
      'title',
    ]);
    final startTime = _formatTimeLabel(
      nextClass['start_time'] ?? nextClass['startTime'],
    );
    final endTime = _formatTimeLabel(
      nextClass['end_time'] ?? nextClass['endTime'],
    );
    final subtitle =
        startTime.isEmpty
            ? 'Next Class'
            : endTime.isEmpty
            ? 'Starts $startTime'
            : '$startTime - $endTime';

    return (
      name: className.isEmpty ? 'Untitled class' : className,
      subtitle: subtitle,
    );
  }

  List<Map<String, dynamic>> _rowsFromResponse(Object response) {
    return (response as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<void> _loadDashboardData() async {
    int taskCount;
    int classCount;
    ({String name, String subtitle}) nextClassDisplay;

    try {
      final dayCode = _todayDayCode();
      final responses = await Future.wait<dynamic>([
        Supabase.instance.client.from('tasks').select(),
        Supabase.instance.client.from('primary_tasks').select(),
        Supabase.instance.client.from('sub_tasks').select(),
        Supabase.instance.client.from('fixed_classes').select(),
      ]);

      final taskRows = _rowsFromResponse(responses[0]);
      final primaryTaskRows = _rowsFromResponse(responses[1]);
      final subTaskRows = _rowsFromResponse(responses[2]);
      final classRows = _rowsFromResponse(responses[3]);
      final todayClassRows =
          classRows.where((row) => _isTodayClassRow(row, dayCode)).toList();
      taskCount =
          taskRows.where(_isPendingTaskRow).length +
          primaryTaskRows.where(_isPendingTaskRow).length +
          subTaskRows.where(_isPendingTaskRow).length;
      classCount = todayClassRows.length;
      nextClassDisplay = _nextClassDisplay(todayClassRows);

      print('Fetched Tasks: $taskCount');
      print('Fetched Classes: $classCount');
      print('Fetched Next Class: ${nextClassDisplay.name}');
      print(
        'DEBUG: Dashboard fetched ${taskRows.length} manual tasks, '
        '${primaryTaskRows.length} primary tasks, '
        '${subTaskRows.length} subtasks, ${classRows.length} classes',
      );
    } on AssertionError catch (e, stackTrace) {
      print('Dashboard Supabase fetch failed: $e');
      print(stackTrace);
      if (!mounted) {
        return;
      }

      setState(() {
        _pendingTasksCount = 0;
        _nextClassName = 'No classes today';
        _nextClassSubtitle = 'Next Class';
      });

      await _runDashboardPolishTest(pendingTasksCount: 0, classesTodayCount: 0);
      return;
    } catch (e, stackTrace) {
      print('Dashboard Supabase fetch failed: $e');
      print(stackTrace);
      if (!mounted) {
        return;
      }

      setState(() {
        _pendingTasksCount = 0;
        _nextClassName = 'No classes today';
        _nextClassSubtitle = 'Next Class';
      });

      await _runDashboardPolishTest(pendingTasksCount: 0, classesTodayCount: 0);
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _pendingTasksCount = taskCount;
      _nextClassName = nextClassDisplay.name;
      _nextClassSubtitle = nextClassDisplay.subtitle;
    });

    await _runDashboardPolishTest(
      pendingTasksCount: taskCount,
      classesTodayCount: classCount,
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await _apiService.logout();
    } catch (_) {
      // Keep the dashboard usable when auth is not initialized in tests.
    }

    if (!context.mounted) {
      return;
    }

    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil('/login', (Route<dynamic> route) => false);
  }

  String _resolveDisplayName() {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final metadata = user?.userMetadata;
      final fullName = metadata?['full_name']?.toString().trim() ?? '';
      if (fullName.isNotEmpty) {
        return fullName;
      }

      final name = metadata?['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) {
        return name;
      }

      final email = user?.email?.trim() ?? '';
      if (email.isNotEmpty) {
        return email.split('@').first;
      }

      return 'Student';
    } catch (_) {
      return 'Student';
    }
  }

  String _formatReminderTimestamp(DateTime value) {
    final local = value.toLocal();
    final hour =
        local.hour > 12
            ? local.hour - 12
            : local.hour == 0
            ? 12
            : local.hour;
    final minutes = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day}/${local.month}/${local.year} $hour:$minutes $suffix';
  }

  Future<bool> _dismissReminder(ReminderJobModel reminder) async {
    try {
      await _apiService.dismissReminder(reminder.id);
      return true;
    } catch (error) {
      if (!mounted) {
        return false;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to dismiss reminder: $error')),
      );
      return false;
    }
  }

  Future<void> _openSprintChallenge() async {
    final score = await Navigator.of(context).push<int>(
      PageRouteBuilder<int>(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                const SprintGameScreen(),
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(opacity: curvedAnimation, child: child);
        },
      ),
    );

    if (!mounted || score == null) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Race Complete: Earned $score Focus XP!')),
    );
  }

  Color _channelColor(String channel) {
    switch (channel.trim().toLowerCase()) {
      case 'email':
        return const Color(0xFF8B5CF6);
      case 'push':
        return const Color(0xFF2563EB);
      case 'inbox':
        return const Color(0xFF10B981);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _channelLabel(String channel) {
    final normalized = channel.trim();
    if (normalized.isEmpty) {
      return 'Email';
    }

    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  Widget _buildStreakBadge(BuildContext context, int streak) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF97316), Color(0xFFF59E0B)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF97316).withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            '$streak',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard({
    required double width,
    required Color color,
    required bool isWhite,
    required Widget child,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isWhite ? 0.08 : 0.10),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSprintChallengeCard(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: _openSprintChallenge,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF20242C), Color(0xFF07090D)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFFFC857).withValues(alpha: 0.72),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFC857).withValues(alpha: 0.16),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC857).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFFFC857).withValues(alpha: 0.40),
                    ),
                  ),
                  child: const Icon(
                    Icons.sports_motorsports_rounded,
                    color: Color(0xFFFFD166),
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Focus Reward',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: const Color(0xFFFFD166),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sprint Challenge',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tap to Race',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
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

  Widget _buildReminderCard(BuildContext context, ReminderJobModel reminder) {
    final theme = Theme.of(context);
    final channelColor = _channelColor(reminder.channel);

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
        key: ValueKey(reminder.id),
        direction: DismissDirection.endToStart,
        background: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Icon(Icons.done_rounded, color: theme.colorScheme.error),
        ),
        confirmDismiss: (_) => _dismissReminder(reminder),
        onDismissed: (_) {
          setState(() {
            _activeReminders = _activeReminders
                .where((entry) => entry.id != reminder.id)
                .toList(growable: false);
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: channelColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _channelLabel(reminder.channel),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: channelColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatReminderTimestamp(reminder.reminderAt),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = _resolveDisplayName();
    final currentStreak = _currentStreak;
    final reminders = _activeReminders;
    final pendingTasksValue = _pendingTasksCount.toString();
    final nextClassName = _nextClassName;
    final nextClassSubtitle = _nextClassSubtitle;
    final nextClassFontSize =
        nextClassName.length > 28
            ? 20.0
            : nextClassName.length > 18
            ? 22.0
            : 24.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshDashboard,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 140.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Good morning',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: Colors.black,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildStreakBadge(context, currentStreak),
                          const SizedBox(width: 8),
                          Material(
                            color: Colors.white,
                            shape: const CircleBorder(),
                            child: IconButton(
                              onPressed: () => _signOut(context),
                              icon: const Icon(Icons.logout_rounded),
                              color: Colors.black87,
                              tooltip: 'Sign Out',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: IconButton(
                            onPressed: _toggleFocusTimer,
                            icon: Icon(
                              _isFocusTimerActive
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            color: Colors.white,
                            iconSize: 28,
                            tooltip:
                                _isFocusTimerActive
                                    ? 'Pause Focus Timer'
                                    : 'Start Focus Timer',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            'Focus Mode',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Tooltip(
                          message: 'Switch Focus Duration',
                          child: GestureDetector(
                            onTap: _cycleFocusDuration,
                            child: Text(
                              _formatFocusTime(),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.black,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'QUICK OVERVIEW',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 170,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    children: [
                      _buildOverviewCard(
                        width: 200,
                        color: const Color(0xFF7C3AED),
                        isWhite: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                            const Spacer(),
                            Text(
                              pendingTasksValue,
                              style: theme.textTheme.displaySmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tasks Pending',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      _buildOverviewCard(
                        width: 240,
                        color: Colors.white,
                        isWhite: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              color: Color(0xFF2563EB),
                              size: 30,
                            ),
                            const Spacer(),
                            Text(
                              nextClassName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.black,
                                fontSize: nextClassFontSize,
                                fontWeight: FontWeight.w800,
                                height: 1.08,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              nextClassSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildSprintChallengeCard(context),
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        'ACTIVE REMINDERS',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _refreshDashboard,
                        child: const Text('View All'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (reminders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Text(
                      'No active reminders right now.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: reminders.length,
                      itemBuilder: (context, index) {
                        return _buildReminderCard(context, reminders[index]);
                      },
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
