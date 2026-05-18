import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'gacha_controller.dart';

class GachaView extends ConsumerStatefulWidget {
  const GachaView({super.key});

  @override
  ConsumerState<GachaView> createState() => _GachaViewState();
}

class _GachaViewState extends ConsumerState<GachaView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  bool _isRolling = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _pullLever() async {
    final state = ref.read(gachaControllerProvider);
    if (state.tokens <= 0 || _isRolling) {
      return;
    }

    setState(() {
      _isRolling = true;
    });
    HapticFeedback.heavyImpact();
    unawaited(_shakeController.repeat(reverse: true));

    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) {
      return;
    }

    final prize = ref.read(gachaControllerProvider.notifier).pullGacha();
    _shakeController
      ..stop()
      ..reset();

    setState(() {
      _isRolling = false;
    });

    if (prize == null) {
      return;
    }

    HapticFeedback.vibrate();
    _showPrizeDialog(prize);
  }

  void _showPrizeDialog(GachaPrize prize) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'NEW LOOT!',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(prize.loot, style: const TextStyle(fontSize: 80)),
              const SizedBox(height: 16),
              Text(
                prize.rarity,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _rarityColor(prize.rarity),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'AWESOME',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
  }

  Color _rarityColor(String rarity) {
    return switch (rarity) {
      'Legendary' => const Color(0xFFFFB300),
      'Rare' => const Color(0xFF7C4DFF),
      _ => const Color(0xFF00A884),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gachaControllerProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.black : const Color(0xFFF5F5F7);
    final cardColor = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final mutedColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final canPull = state.tokens > 0 && !_isRolling;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'MYSTERY BOX',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1),
        ),
        centerTitle: true,
        backgroundColor: backgroundColor,
        foregroundColor: textColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.stars_rounded,
                    color: Colors.amber,
                    size: 32,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${state.tokens} TOKENS',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _shakeController,
                      builder: (context, child) {
                        final wobble =
                            math.sin(_shakeController.value * math.pi * 2) *
                            0.08;
                        return Transform.rotate(
                          angle: _isRolling ? wobble : 0,
                          child: AnimatedScale(
                            scale: _isRolling ? 1.08 : 1,
                            duration: const Duration(milliseconds: 220),
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        width: 168,
                        height: 168,
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF7C4DFF,
                          ).withValues(alpha: isDark ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(36),
                          border: Border.all(
                            color: const Color(
                              0xFF7C4DFF,
                            ).withValues(alpha: 0.28),
                          ),
                        ),
                        child: const Icon(
                          Icons.card_giftcard_rounded,
                          size: 104,
                          color: Color(0xFF7C4DFF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            canPull ? Colors.amber : Colors.grey.shade500,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.grey.shade500,
                        disabledForegroundColor: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 20,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32),
                        ),
                      ),
                      onPressed: canPull ? _pullLever : null,
                      child: Text(
                        _isRolling ? 'ROLLING...' : 'PULL LEVER',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR COLLECTION',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: mutedColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (state.unlockedLoot.isEmpty)
                    Text(
                      'No loot yet',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: mutedColor,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children:
                          state.unlockedLoot.map((item) {
                            return Container(
                              width: 64,
                              height: 64,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:
                                    isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                item,
                                style: const TextStyle(fontSize: 32),
                              ),
                            );
                          }).toList(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
