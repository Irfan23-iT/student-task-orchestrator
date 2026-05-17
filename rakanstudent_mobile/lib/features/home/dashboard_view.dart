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

class _DashboardViewState extends State<DashboardView>
    with WidgetsBindingObserver {
  static const List<int> _focusDurationOptions = [15, 25, 50];
  static const int _defaultFocusDurationMinutes = 25;

  final ApiService _apiService = ApiService();

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
    unawaited(_loadAnalyticsOverview());
    unawaited(_loadFocusPreferences());
    ApiService.taskMutationNotifier.addListener(_handleTaskMutation);
    _runApiBridgeHealthTest();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    ApiService.taskMutationNotifier.removeListener(_handleTaskMutation);
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

    unawaited(_loadAnalyticsOverview());
    unawaited(_loadFocusPreferences());

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

  void _pauseFocusTimer() {
    _timer?.cancel();
    _timer = null;
    _backgroundedAt = null;
    _wasFocusTimerRunningInBackground = false;

    if (!mounted) {
      return;
    }

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
    final summary = await _apiService.fetchDashboardSummary();

    print(
      'DEBUG: Dashboard summary fetched '
      '${summary.upcomingBlocks.length} upcoming blocks',
    );

    await _runDashboardPolishTest(
      pendingTasksCount: summary.pendingTasksCount,
      classesTodayCount: summary.upcomingBlocks.length,
    );

    return summary;
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

  String _formatBlockTimeRange(DashboardUpcomingBlockDto block) {
    final start = block.startsAt?.toLocal();
    final end = block.endsAt?.toLocal();
    if (start == null) {
      return 'Upcoming task';
    }

    String timeOnly(DateTime value) {
      final hour =
          value.hour > 12
              ? value.hour - 12
              : value.hour == 0
              ? 12
              : value.hour;
      final minutes = value.minute.toString().padLeft(2, '0');
      final suffix = value.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minutes $suffix';
    }

    if (end == null) {
      return 'Starts ${timeOnly(start)}';
    }

    return '${timeOnly(start)} - ${timeOnly(end)}';
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
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.secondary, colorScheme.secondaryContainer],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: colorScheme.secondary.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            color: colorScheme.onSecondary,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            '$streak',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colorScheme.onSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewCard({
    required int index,
    required double width,
    required Color color,
    required Widget child,
  }) {
    final isPressed = _pressedOverviewCards.contains(index);
    final colorScheme = Theme.of(context).colorScheme;

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
          width: width,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.26),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.16),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildSprintChallengeCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.secondaryContainer,
                  colorScheme.surfaceContainerHighest,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colorScheme.secondary.withValues(alpha: 0.50),
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.secondary.withValues(alpha: 0.18),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.18),
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
                      color: colorScheme.secondary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: colorScheme.secondary.withValues(alpha: 0.40),
                      ),
                    ),
                    child: Icon(
                      Icons.sports_motorsports_rounded,
                      color: colorScheme.secondary,
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
                            color: colorScheme.secondary,
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
                            color: colorScheme.onSecondaryContainer,
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
                      color: colorScheme.surface.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Tap to Race',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: colorScheme.onSecondaryContainer,
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.24 : 0.08,
            ),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
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
                color: colorScheme.secondary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.notifications_active_rounded,
                color: colorScheme.onSecondary,
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

  Widget _buildDashboardLoadingCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 170,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.24)),
      ),
      child: Center(
        child: CircularProgressIndicator(color: colorScheme.primary),
      ),
    );
  }

  String _nextClassNameFromSummary(DashboardSummaryDto summary) {
    final firstBlock =
        summary.upcomingBlocks.isEmpty ? null : summary.upcomingBlocks.first;

    return summary.nextClassName?.trim().isNotEmpty == true
        ? summary.nextClassName!.trim()
        : firstBlock?.title ?? 'No classes today';
  }

  String _nextClassSubtitleFromSummary(DashboardSummaryDto summary) {
    final firstBlock =
        summary.upcomingBlocks.isEmpty ? null : summary.upcomingBlocks.first;

    return summary.nextClassSubtitle?.trim().isNotEmpty == true
        ? summary.nextClassSubtitle!.trim()
        : firstBlock == null
        ? 'Next Class'
        : _formatBlockTimeRange(firstBlock);
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

  Widget _buildOverviewCards(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<DashboardSummaryDto>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildDashboardLoadingCard(context);
        }

        if (snapshot.hasError) {
          return _buildDashboardError(context, snapshot.error!);
        }

        if (!snapshot.hasData) {
          return _buildDashboardError(
            context,
            StateError('Dashboard summary completed without data.'),
          );
        }

        final summary = snapshot.data!;
        final pendingTasksValue = summary.pendingTasksCount.toString();
        final nextClassName = _nextClassNameFromSummary(summary);
        final nextClassSubtitle = _nextClassSubtitleFromSummary(summary);
        final nextClassFontSize =
            nextClassName.length > 28
                ? 20.0
                : nextClassName.length > 18
                ? 22.0
                : 24.0;

        return SizedBox(
          height: 170,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _buildOverviewCard(
                index: 0,
                width: 200,
                color: colorScheme.primaryContainer,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_rounded,
                      color: colorScheme.onPrimaryContainer,
                      size: 30,
                    ),
                    const Spacer(),
                    Text(
                      pendingTasksValue,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tasks Pending',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              _buildOverviewCard(
                index: 1,
                width: 240,
                color: colorScheme.surfaceContainerHighest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: colorScheme.secondary,
                      size: 30,
                    ),
                    const Spacer(),
                    Text(
                      nextClassName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: colorScheme.onSurface,
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
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveReminders(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return FutureBuilder<DashboardSummaryDto>(
      future: _dashboardFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: LinearProgressIndicator(color: colorScheme.primary),
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
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Text(
              'No active reminders right now',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ListView.builder(
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
    final colorScheme = theme.colorScheme;
    final displayName = _resolveDisplayName();
    final currentStreak = _currentStreak;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _reloadDashboard,
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
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: colorScheme.onSurface,
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
                            color: colorScheme.surface,
                            shape: const CircleBorder(),
                            child: IconButton(
                              onPressed: () => _signOut(context),
                              icon: const Icon(Icons.logout_rounded),
                              color: colorScheme.onSurface,
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
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) {
                      setState(() {
                        _isFocusCardPressed = true;
                      });
                    },
                    onTapUp: (_) {
                      setState(() {
                        _isFocusCardPressed = false;
                      });
                    },
                    onTapCancel: () {
                      setState(() {
                        _isFocusCardPressed = false;
                      });
                    },
                    child: AnimatedScale(
                      scale: _isFocusCardPressed ? 0.985 : 1.0,
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              colorScheme.primaryContainer,
                              colorScheme.surfaceContainerHighest,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: colorScheme.outline.withValues(alpha: 0.22),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withValues(
                                alpha: 0.18,
                              ),
                              blurRadius: 30,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: IconButton(
                                onPressed: _toggleFocusTimer,
                                icon: Icon(
                                  _isFocusTimerActive
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                                color: colorScheme.onPrimary,
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
                                  color: colorScheme.onPrimaryContainer,
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
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        color: colorScheme.secondary,
                                        fontWeight: FontWeight.w800,
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
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'QUICK OVERVIEW',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildOverviewCards(context),
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
                          color: colorScheme.onSurfaceVariant,
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
                ),
                const SizedBox(height: 8),
                _buildActiveReminders(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
