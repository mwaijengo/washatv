// Basic smoke test — the counter starter template no longer matches this app;
// this just confirms the widget tree builds without throwing.

import 'package:flutter_test/flutter_test.dart';

import 'package:washa/app.dart';

void main() {
  testWidgets('WashaApp builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const WashaApp());
    await tester.pump();
  });
}
