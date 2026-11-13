import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _defaultApiBase = 'https://washatv-production.up.railway.app';

/// How long one admin login stays valid. The server enforces the same limit in the JWT.
const adminSessionLifetime = Duration(hours: 24);

/// Admin session handling: sign in with the password only; the session lasts 24 hours.
///
/// The JWT is kept on the device together with the login time. [hasSession] turns false the
/// moment the 24 hours (or the JWT's own `exp`, whichever is earlier) are over, and the
/// dashboard then returns to the password screen. The server rejects the token as well, so
/// changing the phone clock cannot extend a session.
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
  static const _prefsLoginAt = 'washa_admin_login_at_v1';
  // Old builds stored the admin e-mail / a pasted API key. Both are wiped on load.
  static const _legacyEmailKey = 'washa_admin_email_v1';
  static const _legacyRuntimeKey = 'washaAdminRuntimeApiKey';

  final String apiBase;
  String _jwt = '';
  DateTime? _loginAt;
  bool _loaded = false;
  bool _endedByExpiry = false;

  bool get isLoaded => _loaded;
  bool get endedByExpiry => _endedByExpiry;
  String get jwt => _jwt.trim();

  /// True only while a stored JWT exists and the 24 hours have not passed.
  bool get hasSession => _jwt.isNotEmpty && !isExpired;

  /// When the current session ends (earliest of login + 24h and the JWT `exp`).
  DateTime? get expiresAt {
    if (_jwt.isEmpty) return null;
    final byLogin = (_loginAt ?? DateTime.fromMillisecondsSinceEpoch(0)).add(adminSessionLifetime);
    final byJwt = _jwtExpiry(_jwt);
    if (byJwt != null && byJwt.isBefore(byLogin)) return byJwt;
    return byLogin;
  }

  bool get isExpired {
    final end = expiresAt;
    return end == null || !DateTime.now().isBefore(end);
  }

  Duration? get remaining {
    final end = expiresAt;
    if (end == null) return null;
    final d = end.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _jwt = (sp.getString(_prefsJwt) ?? '').trim();
    final at = sp.getInt(_prefsLoginAt);
    _loginAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    await sp.remove(_legacyEmailKey);
    await sp.remove(_legacyRuntimeKey);
    // A session saved before the 24h rule (no login time) or one that already ran out is dropped.
    if (_jwt.isNotEmpty && isExpired) {
      await _clear(sp);
      _endedByExpiry = true;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Logs out when the 24 hours are over. Returns true if the session was just ended.
  Future<bool> expireIfNeeded() async {
    if (_jwt.isEmpty || !isExpired) return false;
    await logout(expired: true);
    return true;
  }

  Map<String, String> headers({String contentType = ''}) {
    final h = <String, String>{'Accept': 'application/json'};
    if (contentType.isNotEmpty) h['Content-Type'] = contentType;
    if (_jwt.isNotEmpty) h['Authorization'] = 'Bearer $_jwt';
    return h;
  }

  /// Returns null on success, or a user-facing (Swahili) error string.
  Future<String?> login({required String password}) async {
    final p = password.trim();
    if (p.isEmpty) return 'Weka neno la siri.';

    try {
      final res = await http
          .post(
            Uri.parse('$apiBase/api/v1/admin/auth/login'),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'password': p}),
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (res.statusCode == 401) return 'Neno la siri si sahihi.';
        if (res.statusCode == 403) return 'Mtandao huu (IP) haujaruhusiwa kuingia admin.';
        if (res.statusCode == 429) return 'Majaribio mengi sana. Subiri dakika 15 kisha jaribu tena.';
        if (res.statusCode == 503) {
          return 'Seva haijasanidi kuingia kwa admin (ADMIN_PASSWORD_HASH).';
        }
        final serverMsg = _readServerError(res.body);
        return serverMsg ?? 'Kuingia kumeshindikana (${res.statusCode}).';
      }

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final token = map['token'] as String?;
      if (token == null || token.isEmpty) return 'Seva haikutuma tokeni ya kuingia.';

      final now = DateTime.now();
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_prefsJwt, token);
      await sp.setInt(_prefsLoginAt, now.millisecondsSinceEpoch);
      _jwt = token;
      _loginAt = now;
      _endedByExpiry = false;
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

  static DateTime? _jwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final exp = (jsonDecode(payload) as Map<String, dynamic>)['exp'];
      if (exp is num) return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
    } catch (_) {}
    return null;
  }

  Future<void> _clear(SharedPreferences sp) async {
    await sp.remove(_prefsJwt);
    await sp.remove(_prefsLoginAt);
    _jwt = '';
    _loginAt = null;
  }

  /// [expired] marks a session that ended by itself (24h over, or the server refused the token),
  /// so the password screen can explain why instead of looking like a random logout.
  Future<void> logout({bool expired = false}) async {
    final sp = await SharedPreferences.getInstance();
    await _clear(sp);
    _endedByExpiry = expired;
    notifyListeners();
  }
}
