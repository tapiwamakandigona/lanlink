import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lanlink/ui/mode_choice_page.dart';

void main() {
  Widget wrap(ValueChanged<bool> onChosen) => MaterialApp(
        home: ModeChoicePage(onChosen: onChosen),
      );

  testWidgets('shows both mode cards and the reassurance line', (tester) async {
    await tester.pumpWidget(wrap((_) {}));
    expect(find.text('How do you want to use LanLink?'), findsOneWidget);
    expect(find.text('Simple'), findsOneWidget);
    expect(find.text('Full'), findsOneWidget);
    expect(find.text('You can switch any time in Settings.'), findsOneWidget);
  });

  testWidgets('tapping Simple reports true', (tester) async {
    bool? chosen;
    await tester.pumpWidget(wrap((v) => chosen = v));
    await tester.tap(find.text('Simple'));
    expect(chosen, isTrue);
  });

  testWidgets('tapping Full reports false', (tester) async {
    bool? chosen;
    await tester.pumpWidget(wrap((v) => chosen = v));
    await tester.tap(find.text('Full'));
    expect(chosen, isFalse);
  });
}
