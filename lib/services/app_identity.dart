import 'package:package_info_plus/package_info_plus.dart';

/// Cached app version/build for bootstrap + payment headers.
class AppIdentity {
  AppIdentity._();

  static String version = '';
  static int build = 0;
  static bool _loaded = false;

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version.trim();
      build = int.tryParse(info.buildNumber.trim()) ?? 0;
    } catch (_) {
      version = '';
      build = 0;
    }
    _loaded = true;
  }

  static Map<String, String> queryParams() {
    final q = <String, String>{};
    if (build > 0) q['appBuild'] = '$build';
    if (version.isNotEmpty) q['appVersion'] = version;
    return q;
  }

  static Map<String, String> headers() {
    final h = <String, String>{};
    if (build > 0) h['X-App-Build'] = '$build';
    if (version.isNotEmpty) h['X-App-Version'] = version;
    return h;
  }

  static Map<String, dynamic> bodyFields() {
    final b = <String, dynamic>{};
    if (build > 0) b['app_build'] = build;
    if (version.isNotEmpty) b['app_version'] = version;
    return b;
  }
}
