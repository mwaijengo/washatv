import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android-only bridge that reports installed traffic-capture apps
/// (HttpCanary, Reqable, PCAPdroid, ...). Mirrors `CaptureProtection.kt`.
class CaptureGuard {
  CaptureGuard._();

  static const _channel = MethodChannel('com.washatv/secure');

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Returns the enabled capture apps, or an empty list when none are found
  /// or the platform has no bridge.
  static Future<List<Map<String, String>>> findCaptureApps() async {
    if (!_supported) return const [];
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('findCaptureApps');
      return (result ?? const <dynamic>[])
          .whereType<Map>()
          .map((app) => <String, String>{
                'packageName': app['packageName']?.toString() ?? '',
                'label': app['label']?.toString() ?? 'Unknown app',
              })
          .where((app) => app['packageName']!.isNotEmpty)
          .toList(growable: false);
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static Future<void> openAppSettings(String packageName) async {
    try {
      await _channel.invokeMethod<void>(
        'openCaptureAppSettings',
        {'packageName': packageName},
      );
    } on PlatformException {
      // Keep the blocker visible if Android cannot open the app settings.
    }
  }
}
