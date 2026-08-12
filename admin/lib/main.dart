import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_dashboard_app.dart';
import 'admin_launch_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const WashaAdminApp(home: AdminLaunchGate()));
}
