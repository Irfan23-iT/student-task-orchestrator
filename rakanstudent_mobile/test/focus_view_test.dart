import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakanstudent_mobile/features/focus/focus_view.dart';

void main() {
  testWidgets('Focus view renders duration setup controls', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FocusView()));

    expect(find.text('Deep Work Room'), findsOneWidget);
    expect(find.text('Set your block'), findsOneWidget);
    expect(find.text('15 min'), findsOneWidget);
    expect(find.text('25 min Pomodoro'), findsOneWidget);
    expect(find.text('45 min'), findsOneWidget);
    expect(find.text('60 min'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Enter Deep Work'), findsOneWidget);
  });
}
