import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:novabolt/screens/nova_core.dart';

void main() {
  const button = Rect.fromLTWH(100, 500, 84, 84);

  test('ship over the button fades it', () {
    expect(shipUnderButton(button, const Offset(142, 542)), isTrue);
  });

  test('ship within the margin counts, beyond it does not', () {
    expect(shipUnderButton(button, const Offset(142, 584 + 23)), isTrue);
    expect(shipUnderButton(button, const Offset(142, 584 + 25)), isFalse);
    expect(shipUnderButton(button, const Offset(100 - 23, 542)), isTrue);
    expect(shipUnderButton(button, const Offset(100 - 25, 542)), isFalse);
  });

  test('ship far above the button does not', () {
    expect(shipUnderButton(button, const Offset(142, 200)), isFalse);
  });

  test('custom margin', () {
    expect(shipUnderButton(button, const Offset(142, 600), margin: 0), isFalse);
    expect(shipUnderButton(button, const Offset(142, 600), margin: 20), isTrue);
  });
}
