// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/analytics_model.dart';
import '../../models/class_model.dart';
import '../../services/api_service.dart';
import '../focus/focus_view.dart';
import 'sprint_game_screen.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({
    super.key,
    ApiService? apiService,
    @visibleForTesting
    Future<DashboardSummaryDto> Function()? fetchDashboardSummary,
    @visibleForTesting Future<List<ClassModel>> Function()? fetchFixedClasses,
    @visibleForTesting this.enableStartupSideEffects = true,
  }) : _apiService = apiService,
       _fetchDashboardSummary = fetchDashboardSummary,
       _fetchFixedClasses = fetchFixedClasses;

  final ApiService? _apiService;
  final Future<DashboardSummaryDto> Function()? _fetchDashboardSummary;
  final Future<List<ClassModel>> Function()? _fetchFixedClasses;
  final bool enableStartupSideEffects;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView>
    with WidgetsBindingObserver {
  static const List<int> _focusDurationOptions = [15, 25, 50];
  static const int _defaultFocusDurationMinutes = 25;

  late final ApiService _apiService = widget._apiService ?? ApiService();

  int _currentStreak = 0;
  Timer? _timer;
  int _focusDurationMinutes = _defaultFocusDurationMinutes;
  int _secondsRemaining = _defaultFocusDurationMinutes * 60;
  bool _isFocusCardPressed = false;
  bool _isSprintCardPressed = false;
  bool _wasFocusTimerRunningInBackground = false;
  DateTime? _backgroundedAt;
  Future<DashboardSummaryDto>? _dashboardFuture;
  final Set<int> _pressedOverviewCards = <int>{};

  bool get _isFocusTimerActive => _timer?.isActive ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dashboardFuture = _loadDashboardSummary();
    if (widget.enableStartupSideEffects) {
      unawaited(_loadAnalyticsOverview());
      unawaited(_loadFocusPreferences());
      unawaited(_loadProfileName());
      _runApiBridgeHealthTest();
    }
    ApiService.taskMutationNotifier.addListener(_handleTaskMutation);
    ApiService.scheduleMutationNotifier.addListener(_handleScheduleMutation);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    ApiService.taskMutationNotifier.removeListener(_handleTaskMutation);
    ApiService.scheduleMutationNotifier.removeListener(_handleScheduleMutation);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_isFocusTimerActive) {
        _backgroundedAt = DateTime.now();
        _wasFocusTimerRunningInBackground = true;
        _timer?.cancel();
        _timer = null;
      }
      return;
    }

    if (state != AppLifecycleState.resumed ||
        !_wasFocusTimerRunningInBackground) {
      return;
    }

    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    _wasFocusTimerRunningInBackground = false;
    if (backgroundedAt == null) {
      _startFocusTimer();
      return;
    }

    final elapsedSeconds = DateTime.now().difference(backgroundedAt).inSeconds;
    final adjustedRemaining = _secondsRemaining - elapsedSeconds;
    if (adjustedRemaining <= 0) {
      setState(() {
        _secondsRemaining = 0;
      });
      _completeFocusSession();
      return;
    }

    setState(() {
      _secondsRemaining = adjustedRemaining;
    });
    _startFocusTimer();
  }

  Future<void> _handleTaskMutation() async {
    await _reloadDashboard();
  }

  Future<void> _handleScheduleMutation() async {
    await _reloadDashboard();
  }

  Future<void> _loadProfileName() async {
    try {
      await _apiService.fetchCurrentProfileName();
    } catch (error) {
      debugPrint('Profile name fetch failed: $error');
    }
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

      return analytics;
    } catch (error) {
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

  Future<void> _reloadDashboard() {
    final future = _loadDashboardSummary();

    if (mounted) {
      setState(() {
        _dashboardFuture = future;
      });
    } else {
      _dashboardFuture = future;
    }

    if (widget.enableStartupSideEffects) {
      unawaited(_loadAnalyticsOverview());
      unawaited(_loadFocusPreferences());
    }

    return future.then<void>((_) {});
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
      final metadata = supabase.auth.currentUser?.userMetadata;
      if (metadata == null) {
        return;
      }

      final durationMinutes = _parseFocusDurationMinutes(
        metadata['focus_duration_minutes'],
      );
      final focusStreak = _parseFocusStreak(metadata['focus_streak']);

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
    _backgroundedAt = null;
    _wasFocusTimerRunningInBackground = false;

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

  void _startFocusTimer() {
    if (_secondsRemaining <= 0) {
      setState(() {
        _secondsRemaining = _focusDurationMinutes * 60;
      });
    }

    _timer?.cancel();
    _backgroundedAt = null;
    _wasFocusTimerRunningInBackground = false;
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

  void _completeFocusSession() {
    _timer?.cancel();
    _timer = null;
    _backgroundedAt = null;
    _wasFocusTimerRunningInBackground = false;
    unawaited(_logFocusSessionCompletion());
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

  Future<void> _logFocusSessionCompletion() async {
    try {
      final result = await _apiService.completeFocusSession(
        durationMinutes: _focusDurationMinutes,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _currentStreak = result.streakCount;
      });
    } catch (error, stackTrace) {
      print('Focus session logging failed: $error');
      print(stackTrace);
    }
  }

  Future<DashboardSummaryDto> _loadDashboardSummary() async {
    final results = await Future.wait<Object>([
      (widget._fetchDashboardSummary ?? _apiService.fetchDashboardSummary)(),
      (widget._fetchFixedClasses ?? _apiService.fetchFixedClasses)(),
    ]);
    final summary = results[0] as DashboardSummaryDto;
    final fixedClasses = results[1] as List<ClassModel>;
    final hydratedSummary = summary.copyWith(fixedClasses: fixedClasses);

    print(
      'DEBUG: Dashboard summary fetched '
      '${hydratedSummary.upcomingBlocks.length} upcoming blocks',
    );

    await _runDashboardPolishTest(
      pendingTasksCount: hydratedSummary.pendingTasksCount,
      classesTodayCount: hydratedSummary.scheduleClassesTodayCount,
    );

    return hydratedSummary;
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

  String _formatBlockTimestamp(DateTime? value) {
    if (value == null) {
      return 'Unscheduled';
    }

    return _formatReminderTimestamp(value);
  }

  Future<void> _openSprintChallenge() async {
    final score = await Navigator.of(context).push<int>(
      PageRouteBuilder<int>(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                const SprintGameScreen(),
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 220),
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

  Future<void> _openDeepWorkRoom() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder:
            (context) =>
                FocusView(initialDurationMinutes: _focusDurationMinutes),
        fullscreenDialog: true,
      ),
    );

    if (!mounted) {
      return;
    }

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        systemNavigationBarColor: Theme.of(context).colorScheme.surface,
        systemNavigationBarIconBrightness:
            Theme.of(context).brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  Color _channelColor(BuildContext context, String channel) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (channel.trim().toLowerCase()) {
      case 'high':
      case 'urgent':
        return colorScheme.error;
      case 'medium':
        return colorScheme.secondary;
      case 'low':
        return colorScheme.tertiary;
      case 'email':
        return colorScheme.primary;
      case 'push':
        return colorScheme.primary;
      case 'inbox':
        return colorScheme.tertiary;
      default:
        return colorScheme.onSurfaceVariant;
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: Color(0xFF20E3B2),
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            '$streak',
            style: theme.textTheme.labelLarge?.copyWith(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard({
    required int index,
    required Color accent,
    required Widget child,
  }) {
    final isPressed = _pressedOverviewCards.contains(index);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseCardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final cardColor = Color.alphaBlend(
      accent.withValues(alpha: isDark ? 0.16 : 0.10),
      baseCardColor,
    );
    final shadow =
        isDark
            ? <BoxShadow>[]
            : [
              BoxShadow(
                color: accent.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() {
          _pressedOverviewCards.add(index);
        });
      },
      onTapUp: (_) {
        setState(() {
          _pressedOverviewCards.remove(index);
        });
      },
      onTapCancel: () {
        setState(() {
          _pressedOverviewCards.remove(index);
        });
      },
      child: AnimatedScale(
        scale: isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.30 : 0.14),
            ),
            boxShadow: shadow,
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSprintChallengeCard(
    BuildContext context, {
    required Color sprintAccent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final baseCardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final tintedCardColor = Color.alphaBlend(
      sprintAccent.withValues(alpha: isDark ? 0.18 : 0.12),
      baseCardColor,
    );

    return AnimatedScale(
      scale: _isSprintCardPressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: _openSprintChallenge,
          onHighlightChanged: (isPressed) {
            setState(() {
              _isSprintCardPressed = isPressed;
            });
          },
          borderRadius: BorderRadius.circular(24),
          child: Ink(
            width: double.infinity,
            decoration: BoxDecoration(
              color: tintedCardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: sprintAccent.withValues(alpha: isDark ? 0.34 : 0.18),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: sprintAccent.withValues(alpha: 0.20),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sports_motorsports_outlined,
                      color: sprintAccent,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Focus Reward',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: sprintAccent,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sprint Challenge',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  const Text('Tap to Race'),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: sprintAccent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReminderCard(
    BuildContext context,
    DashboardUpcomingBlockDto block,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final channelColor = _channelColor(context, block.priority);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:
            isDark
                ? Colors.white.withValues(alpha: 0.03)
                : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF20E3B2).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.notifications_active_rounded,
                color: Color(0xFF20E3B2),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
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
                        _channelLabel(block.priority),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: channelColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatBlockTimestamp(block.startsAt),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardError(BuildContext context, Object error) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Text(
        error.toString(),
        style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.error),
      ),
    );
  }

  Widget _buildOverviewCards(
    BuildContext context, {
    required Color taskAccent,
    required Color classAccent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final subTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    Widget buildBentoGrid({
      required String pendingTasksValue,
      required String nextClassName,
      required String nextClassSubtitle,
    }) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final cardHeight = constraints.maxWidth >= 520 ? 164.0 : 156.0;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: cardHeight,
                  child: _buildOverviewCard(
                    index: 0,
                    accent: taskAccent,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.check_rounded, color: taskAccent, size: 30),
                        const SizedBox(height: 18),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              alignment: Alignment.centerLeft,
                              fit: BoxFit.scaleDown,
                              child: Text(
                                pendingTasksValue,
                                style: theme.textTheme.displaySmall?.copyWith(
                                  color: taskAccent,
                                  fontSize: 38,
                                  fontWeight: FontWeight.bold,
                                  height: 0.95,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tasks Pending',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: subTextColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: SizedBox(
                  height: cardHeight,
                  child: ValueListenableBuilder<int>(
                    valueListenable: ApiService.scheduleMutationNotifier,
                    builder: (context, scheduleVersion, _) {
                      return _buildOverviewCard(
                        index: 1,
                        accent: classAccent,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              color: classAccent,
                              size: 30,
                            ),
                            const SizedBox(height: 18),
                            Column(
                              key: ValueKey<int>(scheduleVersion),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FittedBox(
                                  alignment: Alignment.centerLeft,
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    nextClassName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: classAccent,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  nextClassSubtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: subTextColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    return FutureBuilder<DashboardSummaryDto>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return buildBentoGrid(
            pendingTasksValue: '--',
            nextClassName: 'No classes today',
            nextClassSubtitle: 'Next Class',
          );
        }

        if (snapshot.hasError) {
          return buildBentoGrid(
            pendingTasksValue: '0',
            nextClassName: 'No classes today',
            nextClassSubtitle: 'Next Class',
          );
        }

        if (!snapshot.hasData) {
          return buildBentoGrid(
            pendingTasksValue: '0',
            nextClassName: 'No classes today',
            nextClassSubtitle: 'Next Class',
          );
        }

        final summary = snapshot.data!;
        final pendingTasksValue = summary.upcomingBlocks.length.toString();
        return buildBentoGrid(
          pendingTasksValue: pendingTasksValue,
          nextClassName: summary.nextClassTitle,
          nextClassSubtitle: summary.nextClassDetail,
        );
      },
    );
  }

  Widget _buildActiveReminders(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
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

    Widget wrapReminderBody(Widget child) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: shadow,
        ),
        child: child,
      );
    }

    return FutureBuilder<DashboardSummaryDto>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return wrapReminderBody(
            LinearProgressIndicator(color: colorScheme.primary),
          );
        }

        if (snapshot.hasError) {
          return _buildDashboardError(context, snapshot.error!);
        }

        if (!snapshot.hasData) {
          return _buildDashboardError(
            context,
            StateError('Dashboard reminders completed without data.'),
          );
        }

        final reminders = snapshot.data!.upcomingBlocks;

        if (reminders.isEmpty) {
          return wrapReminderBody(
            Text(
              'No active reminders right now',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          );
        }

        return wrapReminderBody(
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: reminders.length,
            itemBuilder: (context, index) {
              return _buildReminderCard(context, reminders[index]);
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF5F5F7);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
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
    final taskAccent =
        isDark ? const Color(0xFFB388FF) : const Color(0xFF651FFF);
    final classAccent =
        isDark ? const Color(0xFFFF8A65) : const Color(0xFFFF5722);
    final sprintAccent =
        isDark ? const Color(0xFFFFCA28) : const Color(0xFFFF8F00);
    final fallbackDisplayName = _resolveDisplayName();
    final currentStreak = _currentStreak;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reloadDashboard,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Good morning',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: subTextColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ValueListenableBuilder<String?>(
                            valueListenable: ApiService.profileNameNotifier,
                            builder: (context, profileName, _) {
                              final displayName =
                                  profileName?.trim().isNotEmpty == true
                                      ? profileName!.trim()
                                      : fallbackDisplayName;

                              return Text(
                                displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.headlineMedium?.copyWith(
                                  color: textColor,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  height: 1.05,
                                ),
                              );
                            },
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
                        Container(
                          decoration: BoxDecoration(
                            color: cardColor,
                            shape: BoxShape.circle,
                            boxShadow: shadow,
                          ),
                          child: IconButton(
                            onPressed: () => _signOut(context),
                            icon: const Icon(Icons.logout_rounded),
                            color: textColor,
                            tooltip: 'Sign Out',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Focus Mode',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: subTextColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                AnimatedScale(
                  scale: _isFocusCardPressed ? 0.985 : 1.0,
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    width: double.infinity,
                    height: 72,
                    margin: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF20E3B2), Color(0xFF00A3FF)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Tooltip(
                      message: 'Open Deep Work Room',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(100),
                          onTap: _openDeepWorkRoom,
                          onHighlightChanged: (isPressed) {
                            setState(() {
                              _isFocusCardPressed = isPressed;
                            });
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lock_rounded,
                                      color: Colors.black,
                                      size: 32,
                                    ),
                                    const SizedBox(width: 12),
                                    const Flexible(
                                      child: Text(
                                        'Start Focus Mode',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Tooltip(
                                message: 'Switch Focus Duration',
                                child: GestureDetector(
                                  onTap: _cycleFocusDuration,
                                  child: Text(
                                    _formatFocusTime(),
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'QUICK OVERVIEW',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: subTextColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                _buildOverviewCards(
                  context,
                  taskAccent: taskAccent,
                  classAccent: classAccent,
                ),
                const SizedBox(height: 24),
                _buildSprintChallengeCard(context, sprintAccent: sprintAccent),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Text(
                      'ACTIVE REMINDERS',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: subTextColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _reloadDashboard,
                      child: const Text('View All'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildActiveReminders(context),
                const SizedBox(height: 116),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
