import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Admin session handling (Supasoka-style): JWT persisted on device after login.
///
/// Optional compile-time [buildTimeApiKey] (`WASHA_ADMIN_API_KEY`) for release APK/IPA
/// builds via `--dart-define-from-file=admin/dev_defines.json` — no typing each run.
class AdminAuth extends ChangeNotifier {
  AdminAuth({String? apiBase})
      : apiBase = (apiBase ??
                const String.fromEnvironment(
                  'WASHA_API_BASE_URL',
                  defaultValue: 'https://washatv-production.up.railway.app',
                ))
            .replaceAll(RegExp(r'/+$'), '');

  static const _prefsJwt = 'washa_admin_jwt_v1';
  static const _prefsEmail = 'washa_admin_email_v1';
  static const _legacyRuntimeKey = 'washaAdminRuntimeApiKey';

  /// Baked into release builds; same value as Railway `ADMIN_API_KEY`.
  static const String buildTimeApiKey = String.fromEnvironment('WASHA_ADMIN_API_KEY');

  final String apiBase;
  String _jwt = '';
  String _savedEmail = '';
  bool _loaded = false;

  bool get isLoaded => _loaded;
  String get jwt => _jwt.trim();
  String get savedEmail => _savedEmail;

  /// True when JWT is stored, or a compile-time admin key was provided at build.
  bool get hasSession => buildTimeApiKey.isNotEmpty || _jwt.isNotEmpty;

  bool get usesBuildTimeKey => buildTimeApiKey.isNotEmpty && _jwt.isEmpty;

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _jwt = (sp.getString(_prefsJwt) ?? '').trim();
    _savedEmail = (sp.getString(_prefsEmail) ?? '').trim();
    // Drop legacy pasted API keys — JWT login is the supported path on APK.
    if (_jwt.isEmpty && sp.containsKey(_legacyRuntimeKey)) {
      await sp.remove(_legacyRuntimeKey);
    }
    _loaded = true;
    notifyListeners();
  }

  Map<String, String> headers({String contentType = ''}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (contentType.isNotEmpty) h['Content-Type'] = contentType;
    if (_jwt.isNotEmpty) {
      h['Authorization'] = 'Bearer $_jwt';
    } else if (buildTimeApiKey.isNotEmpty) {
      h['X-Admin-Key'] = buildTimeApiKey;
    }
    return h;
  }

  /// Returns null on success, or a user-facing error string.
  Future<String?> login({required String email, required String password}) async {
    final e = email.trim();
    final p = password.trim();
    if (e.isEmpty || p.isEmpty) return 'Weka barua pepe na neno la siri.';

    try {
      final res = await http
          .post(
            Uri.parse('$apiBase/api/v1/admin/auth/login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'email': e, 'password': p}),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (res.statusCode == 401) return 'Barua pepe au neno la siri si sahihi.';
        if (res.statusCode == 503) {
          return 'Seva haijasanidi admin login (ADMIN_EMAIL / ADMIN_PASSWORD_HASH).';
        }
        return 'Kuingia kumeshindikana (${res.statusCode}).';
      }

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final token = map['token'] as String?;
      if (token == null || token.isEmpty) return 'Token haipo kwenye majibu ya seva.';

      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsJwt, token);
      await sp.setString(_prefsEmail, e);
      _jwt = token;
      _savedEmail = e;
      notifyListeners();
      return null;
    } catch (err) {
      if (kDebugMode) debugPrint('AdminAuth.login: $err');
      return 'Hitilafu ya mtandao. Angalia URL ya API na muunganisho.';
    }
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_prefsJwt);
    _jwt = '';
    notifyListeners();
  }
}
