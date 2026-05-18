import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class FocusView extends StatefulWidget {
  const FocusView({super.key, this.initialDurationMinutes = 25});

  final int initialDurationMinutes;

  @override
  State<FocusView> createState() => _FocusViewState();
}

enum _FocusPhase { idle, active, complete }

class _FocusViewState extends State<FocusView>
    with SingleTickerProviderStateMixin {
  static const List<int> _quickDurations = <int>[15, 25, 45, 60];

  late final AnimationController _breathingController;
  late int _targetDurationMinutes;
  late int _secondsRemaining;

  Timer? _timer;
  _FocusPhase _phase = _FocusPhase.idle;

  bool get _isActive => _phase == _FocusPhase.active;

  @override
  void initState() {
    super.initState();
    _targetDurationMinutes = widget.initialDurationMinutes.clamp(5, 120);
    _secondsRemaining = _targetDurationMinutes * 60;
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
      lowerBound: 0,
      upperBound: 1,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _breathingController.dispose();
    unawaited(_restoreHardwareState());
    super.dispose();
  }

  Future<void> _enterDeepWork() async {
    await WakelockPlus.enable();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    HapticFeedback.mediumImpact();

    if (!mounted) {
      return;
    }

    setState(() {
      _phase = _FocusPhase.active;
      _secondsRemaining = _targetDurationMinutes * 60;
    });

    _breathingController.repeat(reverse: true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_secondsRemaining <= 1) {
        timer.cancel();
        _timer = null;
        _completeSession();
        return;
      }

      setState(() {
        _secondsRemaining--;
      });
    });
  }

  Future<void> _completeSession() async {
    _timer?.cancel();
    _timer = null;
    _breathingController.stop();
    await _restoreHardwareState();
    HapticFeedback.heavyImpact();

    if (!mounted) {
      return;
    }

    setState(() {
      _phase = _FocusPhase.complete;
      _secondsRemaining = 0;
    });
  }

  Future<void> _exitSession() async {
    _timer?.cancel();
    _timer = null;
    _breathingController.stop();
    await _restoreHardwareState();
    HapticFeedback.heavyImpact();

    if (!mounted) {
      return;
    }

    setState(() {
      _phase = _FocusPhase.idle;
      _secondsRemaining = _targetDurationMinutes * 60;
    });
  }

  Future<void> _restoreHardwareState() async {
    await WakelockPlus.disable();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _selectDuration(int minutes) {
    if (_isActive) {
      return;
    }

    setState(() {
      _phase = _FocusPhase.idle;
      _targetDurationMinutes = minutes;
      _secondsRemaining = minutes * 60;
    });
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildSetupView(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final mutedColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text(
          'Deep Work Room',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: isDark ? Colors.black : const Color(0xFFF5F5F7),
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            Text(
              _phase == _FocusPhase.complete
                  ? 'Session complete'
                  : 'Set your block',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a duration, then enter a focused full-screen room.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: mutedColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      '$_targetDurationMinutes min',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: const Color(0xFF20E3B2),
                        fontWeight: FontWeight.w900,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children:
                        _quickDurations.map((minutes) {
                          final isSelected = _targetDurationMinutes == minutes;
                          return ChoiceChip(
                            label: Text(
                              minutes == 25
                                  ? '25 min Pomodoro'
                                  : '$minutes min',
                            ),
                            selected: isSelected,
                            onSelected: (_) => _selectDuration(minutes),
                            selectedColor: const Color(0xFF20E3B2),
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.black : textColor,
                              fontWeight: FontWeight.w800,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          );
                        }).toList(),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Custom duration',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Slider(
                    min: 5,
                    max: 120,
                    divisions: 115,
                    value: _targetDurationMinutes.toDouble(),
                    label: '$_targetDurationMinutes min',
                    onChanged: (value) => _selectDuration(value.round()),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _enterDeepWork,
                      icon: const Icon(Icons.lock_rounded),
                      label: const Text('Enter Deep Work'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF20E3B2),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
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

  Widget _buildLockdownView(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: AnimatedBuilder(
                animation: _breathingController,
                builder: (context, child) {
                  final scale = 1 + (_breathingController.value * 0.035);
                  return Transform.scale(scale: scale, child: child);
                },
                child: Text(
                  _formatTime(_secondsRemaining),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 76,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 32,
              child: OutlinedButton.icon(
                onPressed: _exitSession,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Exit Deep Work'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isActive ? _buildLockdownView(context) : _buildSetupView(context),
    );
  }
}
