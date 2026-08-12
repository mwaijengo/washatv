// Basic smoke test — confirms the admin widget tree builds without throwing.

import 'package:admin/admin_dashboard_app.dart';
import 'package:admin/admin_launch_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('WashaAdminApp builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const WashaAdminApp(home: AdminLaunchGate()));
    await tester.pump();
  });
}
