import 'package:admin/admin_dashboard_app.dart';
import 'package:admin/admin_launch_gate.dart';
import 'package:flutter/material.dart';

/// Prefer building/running from `admin/` on device — that APK skips video/Firebase plugins.
/// Root entry remains for Chrome/desktop convenience: `flutter run -t lib/main_admin.dart`.
void main() {
  runApp(const WashaAdminApp(home: AdminLaunchGate()));
}
