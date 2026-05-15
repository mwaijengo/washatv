import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _defaultApiBase = 'https://washatv-production.up.railway.app';

/// Admin session handling (Supasoka-style): JWT persisted on device after login.
///
/// Optional compile-time [buildTimeApiKey] (`WASHA_ADMIN_API_KEY`) for release APK/IPA
/// builds via `--dart-define-from-file=admin/dev_defines.json` — no typing each run.
class AdminAuth extends ChangeNotifier {
  AdminAuth({String? apiBase})
      : apiBase = normalizeApiBase(
          apiBase ??
              const String.fromEnvironment(
                'WASHA_API_BASE_URL',
                defaultValue: _defaultApiBase,
              ),
        );

  /// Ensures HTTPS for Railway/production hosts and strips trailing slashes.
  static String normalizeApiBase(String raw) {
    var base = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return _defaultApiBase;

    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return _defaultApiBase;

    final host = uri.host.toLowerCase();
    if ((host.contains('railway.app') || host.contains('washatv')) && uri.scheme == 'http') {
      base = uri.replace(scheme: 'https').toString().replaceAll(RegExp(r'/+$'), '');
    }
    return base;
  }

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
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': e, 'password': p}),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (res.statusCode == 401) return 'Barua pepe au neno la siri si sahihi.';
        if (res.statusCode == 503) {
          return 'Seva haijasanidi admin login (ADMIN_EMAIL / ADMIN_PASSWORD_HASH).';
        }
        final serverMsg = _readServerError(res.body);
        return serverMsg ?? 'Kuingia kumeshindikana (${res.statusCode}).';
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
    } on TimeoutException {
      return 'Muda wa kuunganisha umeisha. Jaribu tena.';
    } on FormatException {
      return 'Majibu ya seva si sahihi.';
    } catch (err) {
      if (kDebugMode) debugPrint('AdminAuth.login: $err');
      final msg = err.toString().toLowerCase();
      if (msg.contains('failed host lookup') ||
          msg.contains('socketexception') ||
          msg.contains('clientexception') ||
          msg.contains('connection refused') ||
          msg.contains('network is unreachable')) {
        return 'Hitilafu ya mtandao. Hakikisha intaneti imewashwa na jaribu tena.';
      }
      if (msg.contains('handshake') || msg.contains('certificate')) {
        return 'Hitilafu ya usalama wa mtandao (SSL). Tumia https:// kwenye API.';
      }
      return 'Hitilafu ya mtandao. Jaribu tena baadaye.';
    }
  }

  static String? _readServerError(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final err = map['error'];
      if (err is String && err.trim().isNotEmpty) return err.trim();
    } catch (_) {}
    return null;
  }

  Future<void> logout() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_prefsJwt);
    _jwt = '';
    notifyListeners();
  }
}
