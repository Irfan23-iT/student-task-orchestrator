import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakanstudent_mobile/features/gacha/gacha_view.dart';

void main() {
  testWidgets('Gacha view renders local mystery box state', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: GachaView())),
    );

    expect(find.text('MYSTERY BOX'), findsOneWidget);
    expect(find.text('0 TOKENS'), findsOneWidget);
    expect(find.text('PULL LEVER'), findsOneWidget);
    expect(find.text('No loot yet'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
