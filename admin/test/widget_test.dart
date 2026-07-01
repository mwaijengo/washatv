// Basic smoke test — the counter starter template no longer matches this app;
// this just confirms the widget tree builds without throwing.

import 'package:flutter_test/flutter_test.dart';

import 'package:washa/admin/admin_dashboard_app.dart';
import 'package:washa/admin/admin_launch_gate.dart';

void main() {
  testWidgets('WashaAdminApp builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const WashaAdminApp(home: AdminLaunchGate()));
    await tester.pump();
  });
}
