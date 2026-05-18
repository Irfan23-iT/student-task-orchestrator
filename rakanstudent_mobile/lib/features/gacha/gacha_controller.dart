import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final gachaControllerProvider =
    StateNotifierProvider<GachaController, GachaState>((ref) {
      return GachaController();
    });

class GachaState {
  const GachaState({
    this.tasksCompletedToday = 0,
    this.tokens = 0,
    this.unlockedLoot = const <String>[],
  });

  final int tasksCompletedToday;
  final int tokens;
  final List<String> unlockedLoot;

  GachaState copyWith({
    int? tasksCompletedToday,
    int? tokens,
    List<String>? unlockedLoot,
  }) {
    return GachaState(
      tasksCompletedToday: tasksCompletedToday ?? this.tasksCompletedToday,
      tokens: tokens ?? this.tokens,
      unlockedLoot: unlockedLoot ?? this.unlockedLoot,
    );
  }
}

class GachaPrize {
  const GachaPrize({
    required this.loot,
    required this.rarity,
    required this.weight,
  });

  final String loot;
  final String rarity;
  final int weight;
}

class GachaController extends StateNotifier<GachaState> {
  GachaController({Random? random})
    : _random = random ?? Random(),
      super(const GachaState());

  static const List<GachaPrize> prizePool = <GachaPrize>[
    GachaPrize(loot: '🍕', rarity: 'Common', weight: 32),
    GachaPrize(loot: '🎮', rarity: 'Common', weight: 28),
    GachaPrize(loot: '🎸', rarity: 'Rare', weight: 18),
    GachaPrize(loot: '🚀', rarity: 'Rare', weight: 14),
    GachaPrize(loot: '👾', rarity: 'Rare', weight: 6),
    GachaPrize(loot: '👑', rarity: 'Legendary', weight: 1),
    GachaPrize(loot: '🏆', rarity: 'Legendary', weight: 1),
  ];

  final Random _random;

  void incrementTask() {
    final nextCompletedCount = state.tasksCompletedToday + 1;
    if (nextCompletedCount >= 3) {
      state = state.copyWith(tasksCompletedToday: 0, tokens: state.tokens + 1);
      return;
    }

    state = state.copyWith(tasksCompletedToday: nextCompletedCount);
  }

  GachaPrize? pullGacha() {
    if (state.tokens <= 0) {
      return null;
    }

    final prize = _rollPrize();
    state = state.copyWith(
      tokens: state.tokens - 1,
      unlockedLoot: [...state.unlockedLoot, prize.loot],
    );
    return prize;
  }

  GachaPrize _rollPrize() {
    final totalWeight = prizePool.fold<int>(
      0,
      (total, prize) => total + prize.weight,
    );
    var roll = _random.nextInt(totalWeight);

    for (final prize in prizePool) {
      if (roll < prize.weight) {
        return prize;
      }
      roll -= prize.weight;
    }

    return prizePool.last;
  }
}
