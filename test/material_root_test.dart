import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/ui/ui.dart';

/// Game overlays sit straight on a GameWidget, not a Scaffold. Without a
/// Material above them Flutter styles their text with yellow double
/// underlines; `materialRoot` (MaterialApp.builder) prevents that everywhere.
void main() {
  TextStyle styleOf(WidgetTester tester) =>
      DefaultTextStyle.of(tester.element(find.text('overlay text'))).style;

  testWidgets('without materialRoot, bare text gets the underline style', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: Text('overlay text'))));
    expect(styleOf(tester).decoration, TextDecoration.underline);
  });

  testWidgets('with materialRoot, no underline anywhere', (tester) async {
    await tester.pumpWidget(const MaterialApp(builder: materialRoot, home: Center(child: Text('overlay text'))));
    expect(styleOf(tester).decoration, isNot(TextDecoration.underline));
  });
}
