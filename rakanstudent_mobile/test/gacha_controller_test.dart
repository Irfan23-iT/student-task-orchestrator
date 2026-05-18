import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rakanstudent_mobile/features/gacha/gacha_controller.dart';

void main() {
  test('incrementTask awards one token every three completed tasks', () {
    final controller = GachaController();

    controller.incrementTask();
    controller.incrementTask();

    expect(controller.state.tasksCompletedToday, 2);
    expect(controller.state.tokens, 0);

    controller.incrementTask();

    expect(controller.state.tasksCompletedToday, 0);
    expect(controller.state.tokens, 1);
  });

  test('pullGacha consumes one token and adds weighted loot locally', () {
    final controller = GachaController(random: Random(0));

    controller.incrementTask();
    controller.incrementTask();
    controller.incrementTask();

    final prize = controller.pullGacha();

    expect(prize, isNotNull);
    expect(controller.state.tokens, 0);
    expect(controller.state.unlockedLoot, hasLength(1));
    expect(
      GachaController.prizePool.map((prize) => prize.loot),
      contains(controller.state.unlockedLoot.single),
    );
  });

  test('pullGacha does nothing without tokens', () {
    final controller = GachaController();

    final prize = controller.pullGacha();

    expect(prize, isNull);
    expect(controller.state.tokens, 0);
    expect(controller.state.unlockedLoot, isEmpty);
  });
}
