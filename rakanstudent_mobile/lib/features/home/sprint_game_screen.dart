import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SprintGameScreen extends StatefulWidget {
  const SprintGameScreen({super.key, this.startImmediately = true});

  final bool startImmediately;

  @override
  State<SprintGameScreen> createState() => _SprintGameScreenState();
}

class _SprintGameScreenState extends State<SprintGameScreen> {
  static const List<int> _lanes = <int>[-1, 0, 1];
  static const double _playerY = 0.8;
  static const double _enemySpawnY = -1.2;
  static const double _enemyResetY = 1.2;
  static const double _baseGameSpeed = 0.012;
  static const double _maxGameSpeed = 0.032;

  final Random _random = Random();

  Timer? _gameTimer;
  int _playerLane = 0;
  int _enemyLane = 0;
  double _enemyY = _enemySpawnY;
  double _gameSpeed = _baseGameSpeed;
  int _score = 0;
  bool _hasCrashed = false;
  bool _gameOverDialogVisible = false;

  @override
  void initState() {
    super.initState();
    _enemyLane = _randomLane();

    if (widget.startImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        _startGameLoop();
      });
    }
  }

  @override
  void dispose() {
    _gameTimer?.cancel();
    _gameTimer = null;
    super.dispose();
  }

  int _randomLane() {
    return _lanes[_random.nextInt(_lanes.length)];
  }

  double _laneAlignment(int lane) {
    return lane * 0.62;
  }

  void _handleTapDown(TapDownDetails details) {
    if (_hasCrashed) {
      return;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final direction = details.globalPosition.dx < screenWidth / 2 ? -1 : 1;
    final nextLane = (_playerLane + direction).clamp(-1, 1).toInt();

    if (nextLane == _playerLane) {
      return;
    }

    HapticFeedback.selectionClick();

    if (!mounted) {
      return;
    }

    setState(() {
      _playerLane = nextLane;
    });
  }

  void _startGameLoop() {
    _gameTimer?.cancel();
    _gameTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_hasCrashed) {
        timer.cancel();
        return;
      }

      var nextEnemyY = _enemyY + _gameSpeed;
      var nextEnemyLane = _enemyLane;
      var nextScore = _score;
      var nextGameSpeed = _gameSpeed;

      if (nextEnemyY > _enemyResetY) {
        nextScore++;
        nextEnemyY = _enemySpawnY;
        nextEnemyLane = _randomLane();
        nextGameSpeed = min(_gameSpeed + 0.0014, _maxGameSpeed);
      }

      final didCrash =
          nextEnemyLane == _playerLane &&
          nextEnemyY >= 0.65 &&
          nextEnemyY <= 0.85;

      setState(() {
        _enemyY = nextEnemyY;
        _enemyLane = nextEnemyLane;
        _score = nextScore;
        _gameSpeed = nextGameSpeed;
        _hasCrashed = didCrash;
      });

      if (didCrash) {
        _handleCrash(timer);
      }
    });
  }

  void _handleCrash(Timer timer) {
    timer.cancel();
    _gameTimer = null;
    HapticFeedback.mediumImpact();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      unawaited(_showGameOverDialog());
    });
  }

  void _resetGame() {
    _gameTimer?.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _playerLane = 0;
      _enemyLane = _randomLane();
      _enemyY = _enemySpawnY;
      _gameSpeed = _baseGameSpeed;
      _score = 0;
      _hasCrashed = false;
    });

    _startGameLoop();
  }

  Future<void> _showGameOverDialog() async {
    if (!mounted || _gameOverDialogVisible) {
      return;
    }

    _gameOverDialogVisible = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.58),
      builder: (dialogContext) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Dialog(
            elevation: 0,
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF20242C), Color(0xFF07090D)],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: const Color(0xFFFFC857).withValues(alpha: 0.70),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFC857).withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFC857).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFC857).withValues(alpha: 0.48),
                      ),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFFFD166),
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'RACE COMPLETE',
                    style: Theme.of(
                      dialogContext,
                    ).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFFFFD166),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_score Focus XP',
                    style: Theme.of(
                      dialogContext,
                    ).textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) {
                                return;
                              }

                              _resetGame();
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.42),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('RACE AGAIN'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final finalScore = _score;
                            Navigator.of(dialogContext).pop();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) {
                                return;
                              }

                              Navigator.of(context).pop(finalScore);
                            });
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFC857),
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('EXIT TO PITLANE'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (mounted) {
      _gameOverDialogVisible = false;
    }
  }

  Widget _buildHud(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Material(
              color: Colors.black.withValues(alpha: 0.34),
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(_score),
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
                tooltip: 'Exit Race',
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'SPRINT CHALLENGE',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.38),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFFFFC857).withValues(alpha: 0.56),
                ),
              ),
              child: Text(
                'XP ${_score.toString().padLeft(2, '0')}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFFFD166),
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarShell({
    required Color glow,
    required Color border,
    required Widget child,
  }) {
    return Container(
      width: 74,
      height: 88,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.black.withValues(alpha: 0.16),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: 0.34),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07090D),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SprintTrackPainter(
                  scroll: _enemyY,
                  speed: _gameSpeed,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.0,
                    colors: [
                      const Color(0xFFFFC857).withValues(alpha: 0.16),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment(_laneAlignment(_enemyLane), _enemyY),
              child: _buildCarShell(
                glow: Colors.redAccent,
                border: Colors.redAccent.withValues(alpha: 0.62),
                child: const Icon(
                  Icons.directions_car_rounded,
                  color: Colors.redAccent,
                  size: 50,
                ),
              ),
            ),
            AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              alignment: Alignment(_laneAlignment(_playerLane), _playerY),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                child: _buildCarShell(
                  glow: const Color(0xFFFFC857),
                  border: const Color(0xFFFFC857).withValues(alpha: 0.72),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Colors.amberAccent,
                    size: 50,
                  ),
                ),
              ),
            ),
            _buildHud(context),
          ],
        ),
      ),
    );
  }
}

class _SprintTrackPainter extends CustomPainter {
  const _SprintTrackPainter({required this.scroll, required this.speed});

  final double scroll;
  final double speed;

  @override
  void paint(Canvas canvas, Size size) {
    final roadPaint =
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B1F26), Color(0xFF080A0F)],
          ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, roadPaint);

    final shoulderPaint =
        Paint()
          ..color = const Color(0xFFFFC857).withValues(alpha: 0.18)
          ..strokeWidth = 2.4;
    canvas
      ..drawLine(Offset(14, 0), Offset(14, size.height), shoulderPaint)
      ..drawLine(
        Offset(size.width - 14, 0),
        Offset(size.width - 14, size.height),
        shoulderPaint,
      );

    final lanePaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.28)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round;
    final laneWidth = size.width / 3;
    final dashHeight = 34.0;
    final gap = 30.0;
    final offset = (scroll * 260).abs() % (dashHeight + gap);

    for (final x in <double>[laneWidth, laneWidth * 2]) {
      for (
        double y = -dashHeight + offset;
        y < size.height;
        y += dashHeight + gap
      ) {
        canvas.drawLine(Offset(x, y), Offset(x, y + dashHeight), lanePaint);
      }
    }

    final grainPaint = Paint()..color = Colors.white.withValues(alpha: 0.04);
    for (var index = 0; index < 48; index++) {
      final x = ((index * 47) % max(size.width.toInt(), 1)).toDouble();
      final y =
          ((index * 83 + (scroll.abs() * 400).round()) %
                  max(size.height.toInt(), 1))
              .toDouble();
      canvas.drawCircle(Offset(x, y), 1.1, grainPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SprintTrackPainter oldDelegate) {
    return oldDelegate.scroll != scroll || oldDelegate.speed != speed;
  }
}
