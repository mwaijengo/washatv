import 'dart:async';

import 'package:flutter/material.dart';

import 'admin_auth.dart';
import 'admin_dashboard_app.dart';
import 'admin_login_screen.dart';

/// Loads the saved session, then shows the password screen or the dashboard.
/// Watches the clock so the 24-hour session ends even while the app stays open.
class AdminLaunchGate extends StatefulWidget {
  const AdminLaunchGate({super.key});

  @override
  State<AdminLaunchGate> createState() => _AdminLaunchGateState();
}

class _AdminLaunchGateState extends State<AdminLaunchGate> with WidgetsBindingObserver {
  final AdminAuth _auth = AdminAuth();
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_onAuthChanged);
    _auth.load();
    _expiryTimer = Timer.periodic(const Duration(seconds: 20), (_) => unawaited(_auth.expireIfNeeded()));
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_auth.expireIfNeeded());
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
        notice: _auth.endedByExpiry ? 'Kikao kimeisha (saa 24). Weka neno la siri tena.' : null,
        onLoggedIn: () => setState(() {}),
      );
    }
    return AdminScaffold(auth: _auth);
  }
}
