import 'package:flutter/services.dart';

/// Centralized orientation + immersive mode for home vs full-screen playback.
class PlayerOrientation {
  PlayerOrientation._();

  /// Home shell stays portrait; requires MainActivity `fullSensor` in the manifest.
  static Future<void> lockHomePortrait() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  /// Landscape fullscreen playback — immersive UI, no portrait band.
  static Future<void> enterFullscreenPlayer() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  static Future<void> exitFullscreenPlayer() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await lockHomePortrait();
  }
}
