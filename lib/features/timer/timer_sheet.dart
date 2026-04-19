// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/material.dart';

class TimerSheet extends StatefulWidget {
  const TimerSheet({super.key, this.enableCodexTimerTest = false});

  final bool enableCodexTimerTest;

  @override
  State<TimerSheet> createState() => _TimerSheetState();
}

class _TimerSheetState extends State<TimerSheet> {
  static const int _initialTime = 1500;

  int _timeLeft = _initialTime;
  Timer? _timer;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableCodexTimerTest) {
      _runCodexTimerTest();
    }
  }

  Future<void> _runCodexTimerTest() async {
    try {
      print('--- CODEX TIMER TEST START ---');
      _startTimer();
      await Future<void>.delayed(const Duration(seconds: 2));

      if (!mounted) {
        return;
      }

      if (_timeLeft >= _initialTime) {
        throw StateError('Timer did not decrement.');
      }

      print(
        '--- CODEX TIMER TEST SUCCESS: Timer ticked down to $_timeLeft ---',
      );
      _pauseTimer();
      _resetTimer();
    } catch (e) {
      print('--- CODEX TIMER TEST FAILED: $e ---');
      _pauseTimer();
      _resetTimer();
    }
  }

  void _startTimer() {
    if (_isRunning || _timeLeft <= 0) {
      return;
    }

    setState(() {
      _isRunning = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        if (_timeLeft > 0) {
          _timeLeft--;
        } else {
          _isRunning = false;
          _timer?.cancel();
        }
      });
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    _timer = null;

    if (!mounted) {
      return;
    }

    setState(() {
      _isRunning = false;
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = null;

    if (!mounted) {
      return;
    }

    setState(() {
      _timeLeft = _initialTime;
      _isRunning = false;
    });
  }

  String _formatTime(int timeLeft) {
    final minutes = timeLeft ~/ 60;
    final seconds = timeLeft % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: SizedBox(
          height: 320,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Pomodoro Timer',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _formatTime(_timeLeft),
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _startTimer,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _pauseTimer,
                    icon: const Icon(Icons.pause_rounded),
                    label: const Text('Pause'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _resetTimer,
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Reset'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
