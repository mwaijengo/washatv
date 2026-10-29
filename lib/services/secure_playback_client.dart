import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/channel.dart';
import 'app_identity.dart';

enum PlaybackDenial {
  premiumRequired,
  deviceBlocked,
  updateRequired,
  untrustedDevice,
  unsupportedPlatform,
  unavailable,
  rateLimited,
  network,
}

class PlaybackAccessException implements Exception {
  const PlaybackAccessException(this.reason);

  final PlaybackDenial reason;

  String get userMessage => switch (reason) {
        PlaybackDenial.premiumRequired => 'Channel hii ni ya premium. Lipia kifurushi ili kuitazama.',
        PlaybackDenial.deviceBlocked => 'Kifaa hiki kimezuiwa. Wasiliana nasi kwa msaada.',
        PlaybackDenial.updateRequired => 'Sasisha WASHA TV ili kuendelea kutazama.',
        PlaybackDenial.untrustedDevice =>
          'Kifaa hiki hakiaminiki (debugger au programu za kubadilisha app). Ondoa kisha jaribu tena.',
        PlaybackDenial.unsupportedPlatform => 'Kutazama kunapatikana kwenye app ya Android pekee.',
        PlaybackDenial.unavailable => 'Channel hii haipatikani kwa sasa.',
        PlaybackDenial.rateLimited => 'Maombi mengi sana. Subiri kidogo kisha jaribu tena.',
        PlaybackDenial.network => 'Imeshindikana kufungua channel. Angalia mtandao kisha jaribu tena.',
      };

  @override
  String toString() => 'PlaybackAccessException($reason)';
}

/// Opens short-lived viewer sessions and resolves stream URLs at play time.
/// Signing and payload decryption happen natively; nothing here is written to disk.
class SecurePlaybackClient {
  SecurePlaybackClient({required this.baseUrl});

  final String baseUrl;

  static const _native = MethodChannel('com.washatv/secure');
  static const _timeout = Duration(seconds: 20);

  String? _token;
  String? _sessionId;
  String? _sessionDeviceId;
  DateTime? _expiresAt;
  Future<void>? _sessionInFlight;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _sessionValidFor(String deviceId) {
    final exp = _expiresAt;
    return _token != null &&
        _sessionDeviceId == deviceId &&
        exp != null &&
        DateTime.now().isBefore(exp.subtract(const Duration(minutes: 2)));
  }

  void invalidate() {
    _token = null;
    _sessionId = null;
    _sessionDeviceId = null;
    _expiresAt = null;
  }

  /// Bearer header for endpoints that return more data to the device owner; empty when no session.
  Future<Map<String, String>> authHeadersFor(String deviceId) async {
    if (!supported || deviceId.isEmpty) return const {};
    try {
      await _ensureSession(deviceId);
    } catch (_) {
      return const {};
    }
    final t = _token;
    return t == null ? const {} : {'Authorization': 'Bearer $t'};
  }

  Future<void> _ensureSession(String deviceId) {
    if (_sessionValidFor(deviceId)) return Future.value();
    return _sessionInFlight ??= _openSession(deviceId).whenComplete(() => _sessionInFlight = null);
  }

  Future<void> _openSession(String deviceId) async {
    await AppIdentity.ensureLoaded();
    final chalRes = await http
        .post(
          Uri.parse('$baseUrl/api/v1/public/session/challenge'),
          headers: const {'Content-Type': 'application/json'},
          body: '{}',
        )
        .timeout(_timeout);
    _throwForStatus(chalRes);
    final challenge = (jsonDecode(chalRes.body) as Map)['challenge']?.toString() ?? '';
    if (challenge.isEmpty) throw const PlaybackAccessException(PlaybackDenial.network);

    final Map<Object?, Object?>? proof;
    try {
      proof = await _native.invokeMapMethod<Object?, Object?>('signSession', {
        'challenge': challenge,
        'deviceId': deviceId,
      });
    } on PlatformException catch (e) {
      throw PlaybackAccessException(
        e.code == 'untrusted_device' ? PlaybackDenial.untrustedDevice : PlaybackDenial.unsupportedPlatform,
      );
    } on MissingPluginException {
      throw const PlaybackAccessException(PlaybackDenial.unsupportedPlatform);
    }
    if (proof == null) throw const PlaybackAccessException(PlaybackDenial.unsupportedPlatform);

    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/public/session'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'challenge': challenge,
            'device_id': deviceId,
            'package': proof['package'],
            'cert_sha256': proof['cert_sha256'],
            'flags': proof['flags'],
            'signature': proof['signature'],
            ...AppIdentity.bodyFields(),
          }),
        )
        .timeout(_timeout);
    _throwForStatus(res);
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final token = map['token']?.toString() ?? '';
    final sid = map['session_id']?.toString() ?? '';
    final ttl = (map['expires_in'] as num?)?.toInt() ?? 3600;
    if (token.isEmpty || sid.isEmpty) throw const PlaybackAccessException(PlaybackDenial.network);
    _token = token;
    _sessionId = sid;
    _sessionDeviceId = deviceId;
    _expiresAt = DateTime.now().add(Duration(seconds: ttl));
  }

  /// Returns [channel] with its stream filled in, ready for the player. Never cache the result.
  Future<Channel> resolve({required String deviceId, required Channel channel}) async {
    if (!supported) throw const PlaybackAccessException(PlaybackDenial.unsupportedPlatform);
    if (channel.apiId.isEmpty) throw const PlaybackAccessException(PlaybackDenial.unavailable);

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _ensureSession(deviceId);
      } on PlaybackAccessException {
        rethrow;
      } catch (_) {
        throw const PlaybackAccessException(PlaybackDenial.network);
      }

      final http.Response res;
      try {
        res = await http
            .post(
              Uri.parse('$baseUrl/api/v1/public/playback'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_token',
              },
              body: jsonEncode({'channel_id': channel.apiId}),
            )
            .timeout(_timeout);
      } catch (_) {
        throw const PlaybackAccessException(PlaybackDenial.network);
      }

      if (res.statusCode == 401 && attempt == 0) {
        invalidate();
        continue;
      }
      _throwForStatus(res);

      final sealed = (jsonDecode(res.body) as Map)['sealed']?.toString() ?? '';
      final String? plain;
      try {
        plain = await _native.invokeMethod<String>('openSealed', {
          'sessionId': _sessionId,
          'deviceId': deviceId,
          'sealed': sealed,
        });
      } on PlatformException {
        invalidate();
        throw const PlaybackAccessException(PlaybackDenial.network);
      }
      final data = jsonDecode(plain ?? '{}') as Map<String, dynamic>;
      final url = data['stream_url']?.toString().trim() ?? '';
      if (url.isEmpty) throw const PlaybackAccessException(PlaybackDenial.unavailable);
      final key = data['drm_clear_key']?.toString().trim() ?? '';
      return channel.withResolvedStream(
        streamUrl: url,
        drm: parseChannelDrm(data['drm']),
        drmClearKey: key.isEmpty ? null : key,
      );
    }
    throw const PlaybackAccessException(PlaybackDenial.network);
  }

  static void _throwForStatus(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    String error = '';
    try {
      error = (jsonDecode(res.body) as Map)['error']?.toString() ?? '';
    } catch (_) {}
    throw PlaybackAccessException(switch (res.statusCode) {
      402 => PlaybackDenial.premiumRequired,
      404 => PlaybackDenial.unavailable,
      426 => PlaybackDenial.updateRequired,
      429 => PlaybackDenial.rateLimited,
      403 => error == 'device_blocked' ? PlaybackDenial.deviceBlocked : PlaybackDenial.untrustedDevice,
      401 => error == 'untrusted_client' ? PlaybackDenial.untrustedDevice : PlaybackDenial.network,
      _ => PlaybackDenial.network,
    });
  }
}
