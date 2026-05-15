import 'package:flutter/material.dart';

import 'admin_auth.dart';
import 'admin_dashboard_app.dart';
import 'admin_login_screen.dart';

/// Loads saved JWT (or build-time key), then shows login or the dashboard.
class AdminLaunchGate extends StatefulWidget {
  const AdminLaunchGate({super.key});

  @override
  State<AdminLaunchGate> createState() => _AdminLaunchGateState();
}

class _AdminLaunchGateState extends State<AdminLaunchGate> {
  final AdminAuth _auth = AdminAuth();

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
    _auth.load();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_auth.hasSession) {
      return AdminLoginScreen(
        auth: _auth,
        onLoggedIn: () => setState(() {}),
      );
    }
    return AdminScaffold(auth: _auth);
  }
}
