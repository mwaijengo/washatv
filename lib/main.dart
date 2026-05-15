import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WashaApp());
  unawaited(_initializePushNotifications());
}

/// FCM + Supasoka shared topics — must not block first frame.
Future<void> _initializePushNotifications() async {
  try {
    await PushNotificationService.initialize();
  } catch (e, st) {
    if (kDebugMode) debugPrint('Washa FCM init failed: $e\n$st');
  }
}
