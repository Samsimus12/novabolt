import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/ui/ui.dart';

/// The primary button animates between enabled and disabled. Its decoration
/// must stay lerpable (gradient to gradient): a colour-to-gradient lerp
/// produced a ShapeDecoration with both and threw (seen in the Shop when
/// switching tabs flipped "Equipped" to "Buy").
void main() {
  testWidgets('toggling a primary button enabled/disabled never throws mid-animation', (t) async {
    var enabled = false;
    late StateSetter set;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (context, s) {
          set = s;
          return Center(child: NbButton(label: 'Buy', onPressed: enabled ? () {} : null));
        }),
      ),
    ));
    for (var i = 0; i < 4; i++) {
      set(() => enabled = !enabled);
      for (var f = 0; f < 12; f++) {
        await t.pump(const Duration(milliseconds: 16));
        expect(t.takeException(), isNull);
      }
    }
  });
}
