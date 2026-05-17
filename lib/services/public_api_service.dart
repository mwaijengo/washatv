import 'dart:convert';

import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../admin/admin_currency.dart';
import '../models/channel.dart';
import '../models/hero_slide.dart';
import '../models/plan.dart';
import '../models/viewer_profile.dart';
import 'payment_config.dart';
import 'pricing_catalog.dart';

const _prefsBootstrapCache = 'washatv_bootstrap_cache_v1';
const _prefsBootstrapSyncSig = 'washatv_bootstrap_sync_sig_v1';

/// Railway cold starts can exceed 10s; lightweight polls use this limit.
const _lightweightPollTimeout = Duration(seconds: 22);

void _throttledApiLog(String tag, Object error) {
  if (!kDebugMode) return;
  _ApiLogThrottle.log(tag, error);
}

class _ApiLogThrottle {
  static final _last = <String, DateTime>{};
  static final _burstCount = <String, int>{};
  static final _burstStart = <String, DateTime>{};

  static void log(String tag, Object error) {
    final now = DateTime.now();
    final burstAt = _burstStart[tag];
    if (burstAt == null || now.difference(burstAt) > const Duration(seconds: 3)) {
      _burstStart[tag] = now;
      _burstCount[tag] = 0;
    }
    _burstCount[tag] = (_burstCount[tag] ?? 0) + 1;
    if (_burstCount[tag]! > 1) return;

    final prev = _last[tag];
    if (prev != null && now.difference(prev).inSeconds < 90) return;
    _last[tag] = now;
    debugPrint('WASHA $tag: $error');
  }
}

class PublicBootstrapMeta {
  const PublicBootstrapMeta({required this.version, required this.configSyncedAt});

  final int version;
  final int configSyncedAt;

  String get syncSignature => '$version:$configSyncedAt';
}

class PublicBootstrapData {
  PublicBootstrapData({
    required this.version,
    required this.configSyncedAt,
    required this.channels,
    required this.slides,
    required this.plans,
    required this.whatsappNumber,
    this.subscriptionEnabled = true,
    this.maintenanceMode = false,
    this.siteName = 'WASHA TV',
  });

  final int version;
  final int configSyncedAt;
  final List<Channel> channels;
  final List<HeroSlide> slides;
  final List<Plan> plans;
  final String whatsappNumber;
  final bool subscriptionEnabled;
  final bool maintenanceMode;
  final String siteName;

  String get syncSignature => '$version:$configSyncedAt';
}

/// Avoid proxy caching stale JSON on mobile/desktop. On **web**, omit these headers so the
/// browser sends a [simple CORS request](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS#simple_requests)
/// from `localhost` — `Cache-Control` / `Pragma` trigger a preflight that can surface as
/// `ClientException: Failed to fetch` even when `/health` works in the address bar.
Map<String, String> get _fetchNoStoreHeaders => const {
  'Cache-Control': 'no-cache',
  'Pragma': 'no-cache',
};

Map<String, String> get _publicGetHeaders => kIsWeb ? <String, String>{} : _fetchNoStoreHeaders;

int _safeInt(Object? raw, {int fallback = 0}) {
  if (raw is int) return raw < 0 ? fallback : raw;
  if (raw is num) {
    final d = raw.toDouble();
    if (d.isNaN || !d.isFinite) return fallback;
    return d.toInt();
  }
  if (raw is String) return int.tryParse(raw.trim()) ?? fallback;
  return fallback;
}

int _parseConfigVersionJson(Object? raw) => _safeInt(raw);

bool _planRowEnabled(Object? v) {
  if (v == null) return true;
  if (v is bool) return v;
  if (v is num) return v != 0;
  final s = v.toString().trim().toLowerCase();
  return s == 'true' || s == '1' || s == 't';
}

double? _planRowDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int? _planRowInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

String? _planRowString(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Parses `pricing_plans` rows from bootstrap or `GET /public/plans` (handles string numerics from some DB drivers).
List<Plan> parsePricingPlansFromJsonList(List<dynamic> rawList) {
  final plans = <Plan>[];
  for (final item in rawList) {
    if (item is! Map) continue;
    final j = item.cast<String, dynamic>();
    if (!_planRowEnabled(j['enabled'])) continue;
    final id = _planRowString(j['plan_key'] ?? j['planKey']);
    final name = _planRowString(j['name']);
    final price = _planRowDouble(j['price']);
    final days = _planRowInt(j['duration_days'] ?? j['durationDays']);
    if (id == null || name == null || price == null || days == null) continue;
    plans.add(
      Plan(
        id: id,
        name: name,
        price: fmtTzs(price),
        subtitle: planPeriodSubtitle(days),
        days: days,
      ),
    );
  }
  plans.sort((a, b) {
    final ia = kPlanIdsOrdered.indexOf(a.id);
    final ib = kPlanIdsOrdered.indexOf(b.id);
    if (ia == -1 && ib == -1) return a.id.compareTo(b.id);
    if (ia == -1) return 1;
    if (ib == -1) return -1;
    return ia.compareTo(ib);
  });
  return plans;
}

class PublicApiService {
  /// [baseUrl] defaults to the Washa API on Railway unless `--dart-define=WASHA_API_BASE_URL=...` overrides it (e.g. local backend).
  PublicApiService({String? baseUrl})
      : baseUrl = (baseUrl ?? const String.fromEnvironment('WASHA_API_BASE_URL', defaultValue: 'https://washatv-production.up.railway.app')).replaceAll(RegExp(r'/+$'), '');

  final String baseUrl;

  /// True when the app talks to a machine-local Washa API (dev checkout without SonicPesa).
  bool get isLocalDevelopment => PaymentConfig.isLocalApiHost(baseUrl);

  /// Consecutive failed lightweight polls (network / timeout).
  int consecutiveMetaFailures = 0;

  /// When set, callers should skip meta/profile polls until this time.
  DateTime? metaBackoffUntil;

  bool get shouldSkipLightweightPoll {
    final until = metaBackoffUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  void _noteMetaSuccess() {
    consecutiveMetaFailures = 0;
    metaBackoffUntil = null;
  }

  /// Call after a successful full bootstrap so background polls resume immediately.
  void resetLightweightPollBackoff() => _noteMetaSuccess();

  void _noteMetaFailure() {
    consecutiveMetaFailures++;
    final seconds = (8 * consecutiveMetaFailures).clamp(8, 90);
    metaBackoffUntil = DateTime.now().add(Duration(seconds: seconds));
  }

  /// Full bootstrap (always returns data; never 304).
  Future<PublicBootstrapData> fetchBootstrap() async {
    final data = await fetchBootstrapSince(0);
    if (data == null) {
      throw Exception('Bootstrap failed: unexpected empty response');
    }
    return data;
  }

  /// Cheap poll target (Supasoka `/config-meta` pattern).
  Future<PublicBootstrapMeta?> fetchBootstrapMeta() async {
    if (shouldSkipLightweightPoll) return null;
    final uri = Uri.parse('$baseUrl/api/v1/public/bootstrap-meta').replace(
      queryParameters: {'_': '${DateTime.now().millisecondsSinceEpoch}'},
    );
    try {
      final res = await http.get(uri, headers: _publicGetHeaders).timeout(_lightweightPollTimeout);
      if (res.statusCode != 200) {
        if (res.statusCode == 404) return null;
        _noteMetaFailure();
        return null;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final version = _parseConfigVersionJson(map['version']);
      if (version <= 0 && map['ok'] != true) return null;
      _noteMetaSuccess();
      return PublicBootstrapMeta(
        version: version > 0 ? version : 1,
        configSyncedAt: _parseConfigVersionJson(map['configSyncedAt']),
      );
    } catch (e) {
      _noteMetaFailure();
      _throttledApiLog('bootstrap-meta', e);
      return null;
    }
  }

  /// Fallback when `/bootstrap-meta` is missing (older API deploy).
  Future<int?> fetchConfigVersionOnly() async {
    final uri = Uri.parse('$baseUrl/api/v1/public/config').replace(
      queryParameters: {'_': '${DateTime.now().millisecondsSinceEpoch}'},
    );
    try {
      final res = await http.get(uri, headers: _publicGetHeaders).timeout(_lightweightPollTimeout);
      if (res.statusCode == 304) return null;
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      return _parseConfigVersionJson(map['version']);
    } catch (_) {
      return null;
    }
  }

  /// Returns remote sync signature if admin changed data since [localSignature]; else null.
  Future<String?> fetchBootstrapMetaIfChanged(String? localSignature, {int localVersion = 0}) async {
    if (shouldSkipLightweightPoll) return null;
    final meta = await fetchBootstrapMeta();
    if (meta != null) {
      final remote = meta.syncSignature;
      if (localSignature != null && localSignature == remote) return null;
      return remote;
    }
    // Only hit legacy `/config` when meta endpoint is missing — not on network errors.
    if (consecutiveMetaFailures == 0) {
      final remoteVersion = await fetchConfigVersionOnly();
      if (remoteVersion != null && remoteVersion > localVersion) {
        return '$remoteVersion:0';
      }
    }
    return null;
  }

  /// Name, premium window, plan — used after admin grants or payments.
  Future<ViewerProfile?> fetchViewerProfile(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return null;
    if (shouldSkipLightweightPoll) return null;
    final uri = Uri.parse('$baseUrl/api/v1/public/user-profile/${Uri.encodeComponent(id)}');
    try {
      final res = await http.get(uri, headers: _publicGetHeaders).timeout(_lightweightPollTimeout);
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (map['ok'] != true) return null;

      DateTime? parseMs(Object? raw) {
        if (raw == null) return null;
        final ms = raw is int ? raw : raw is num ? raw.toInt() : int.tryParse(raw.toString());
        if (ms == null || ms <= 0) return null;
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }

      final name = (map['name'] as String?)?.trim() ?? '';
      return ViewerProfile(
        name: name,
        phone: (map['phone'] as String?)?.trim() ?? '',
        premiumActive: map['premiumActive'] == true,
        premiumUntil: parseMs(map['premiumUntilMs']),
        adminAccessUntil: parseMs(map['adminAccessUntilMs']),
        planKey: (map['plan_key'] as String?)?.trim(),
        planName: (map['plan_name'] as String?)?.trim(),
        accessSource: (map['accessSource'] as String?)?.trim() ?? 'none',
      );
    } catch (e) {
      _noteMetaFailure();
      _throttledApiLog('user-profile', e);
      return null;
    }
  }

  /// Server premium expiry for this device (admin grants + completed payments).
  Future<DateTime?> fetchPremiumUntil(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty) return null;
    final uri = Uri.parse('$baseUrl/api/v1/public/user-premium/${Uri.encodeComponent(id)}');
    try {
      final res = await http.get(uri, headers: _publicGetHeaders).timeout(_lightweightPollTimeout);
      if (res.statusCode != 200) return null;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      if (map['ok'] != true) return null;
      final raw = map['premiumUntilMs'];
      if (raw == null) return null;
      final ms = raw is int ? raw : raw is num ? raw.toInt() : int.tryParse(raw.toString());
      if (ms == null || ms <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (e) {
      if (kDebugMode) debugPrint('WASHA user-premium: $e');
      return null;
    }
  }

  Future<void> persistBootstrapCache(PublicBootstrapData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsBootstrapCache, jsonEncode(_bootstrapToJson(data)));
      await prefs.setString(_prefsBootstrapSyncSig, data.syncSignature);
    } catch (_) {}
  }

  Future<PublicBootstrapData?> loadBootstrapCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsBootstrapCache);
      if (raw == null || raw.isEmpty) return null;
      return _parseBootstrapBody(raw);
    } catch (_) {
      return null;
    }
  }

  Future<String?> loadBootstrapSyncSignature() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsBootstrapSyncSig);
    } catch (_) {
      return null;
    }
  }

  /// Uses server [`since` query](bootstrap) support: returns `null` when config is unchanged (HTTP 304),
  /// so the viewer app can poll in one round-trip without re-downloading JSON.
  Future<PublicBootstrapData?> fetchBootstrapSince(int sinceConfigVersion) async {
    final uri = Uri.parse('$baseUrl/api/v1/public/bootstrap').replace(
      queryParameters: <String, String>{
        'since': '$sinceConfigVersion',
        '_': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final res = await http.get(uri, headers: _publicGetHeaders).timeout(const Duration(seconds: 25));
        if (res.statusCode == 304) return null;
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('Bootstrap failed: ${res.statusCode}');
        }
        final data = _parseBootstrapBody(res.body);
        await persistBootstrapCache(data);
        return data;
      } catch (e) {
        lastError = e;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(milliseconds: 350 * (1 << attempt)));
        }
      }
    }
    throw lastError ?? Exception('Bootstrap failed');
  }

  /// Enabled plans from DB only (`GET /api/v1/public/plans`). Use when bootstrap `plans` parses empty but the API is up.
  Future<List<Plan>> fetchPublicPlans() async {
    final uri = Uri.parse('$baseUrl/api/v1/public/plans');
    final res = await http.get(uri, headers: _publicGetHeaders).timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Plans failed: ${res.statusCode}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = (map['plans'] as List?)?.cast<dynamic>() ?? const [];
    return parsePricingPlansFromJsonList(raw);
  }

  PublicBootstrapData _parseBootstrapBody(String body) {
    final map = jsonDecode(body) as Map<String, dynamic>;
    final settings = (map['settings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final rawPlans = (map['plans'] as List?)?.cast<dynamic>() ?? const [];
    final rawChannels = (map['channels'] as List?)?.cast<dynamic>() ?? const [];
    final rawSlides = (map['slides'] as List?)?.cast<dynamic>() ?? const [];

    final plans = parsePricingPlansFromJsonList(rawPlans);

    final channels = <Channel>[];
    for (final item in rawChannels) {
      if (item is! Map) continue;
      final j = item.cast<String, dynamic>();
      final status = (j['status'] as String?) ?? 'active';
      if (status != 'active') continue;
      final name = (j['name'] as String?)?.trim();
      final thumb = (j['thumbnail'] as String?)?.trim();
      final category = (j['category'] as String?)?.trim();
      if (name == null || name.isEmpty || thumb == null || thumb.isEmpty || category == null || category.isEmpty) continue;
      final stream = (j['stream_url'] as String?)?.trim() ?? (j['streamUrl'] as String?)?.trim() ?? '';
      final drmRaw = (j['drm'] as String?)?.trim().toLowerCase() ?? 'none';
      final drm = switch (drmRaw) {
        'clearkey' => ChannelDrm.clearkey,
        'widevine' => ChannelDrm.widevine,
        _ => ChannelDrm.none,
      };
      channels.add(
        Channel(
          id: _channelNumericId(j['id']),
          name: name,
          premium: j['premium'] as bool? ?? false,
          imageUrl: thumb,
          live: j['live'] as bool? ?? false,
          category: category,
          streamUrl: stream,
          drm: drm,
        ),
      );
    }

    final slides = <HeroSlide>[];
    for (final item in rawSlides) {
      if (item is! Map) continue;
      final j = item.cast<String, dynamic>();
      final slideActive = j['active'] as bool? ?? true;
      if (!slideActive) continue;
      final title = (j['title'] as String?)?.trim();
      final subtitle = (j['subtitle'] as String?)?.trim() ?? '';
      final imageUrl = (j['image_url'] as String?)?.trim();
      if (title == null || title.isEmpty || imageUrl == null || imageUrl.isEmpty) continue;
      slides.add(
        HeroSlide(
          id: (j['id'] as String?)?.trim() ?? 'SL-${slides.length + 1}',
          title: title,
          subtitle: subtitle,
          imageUrl: imageUrl,
          premium: j['premium'] as bool? ?? false,
          active: slideActive,
          sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    slides.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return PublicBootstrapData(
      version: _parseConfigVersionJson(map['version']),
      configSyncedAt: _parseConfigVersionJson(map['configSyncedAt']),
      channels: channels,
      slides: slides,
      plans: plans,
      whatsappNumber: (settings['whatsapp_number'] as String?)?.trim() ?? '',
      subscriptionEnabled: settings['subscription_enabled'] as bool? ?? true,
      maintenanceMode: settings['maintenance_mode'] as bool? ?? false,
      siteName: (settings['site_name'] as String?)?.trim().isNotEmpty == true
          ? (settings['site_name'] as String).trim()
          : 'WASHA TV',
    );
  }

  Map<String, dynamic> _bootstrapToJson(PublicBootstrapData d) => {
        'version': d.version,
        'configSyncedAt': d.configSyncedAt,
        'settings': {
          'whatsapp_number': d.whatsappNumber,
          'subscription_enabled': d.subscriptionEnabled,
          'maintenance_mode': d.maintenanceMode,
          'site_name': d.siteName,
        },
        'plans': d.plans
            .map(
              (p) => {
                'plan_key': p.id,
                'name': p.name,
                'price': double.tryParse(p.price.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0,
                'duration_days': p.days,
                'enabled': true,
              },
            )
            .toList(),
        'channels': d.channels
            .map(
              (c) => {
                'id': c.id,
                'name': c.name,
                'category': c.category,
                'premium': c.premium,
                'live': c.live,
                'status': 'active',
                'thumbnail': c.imageUrl,
                'stream_url': c.streamUrl,
              },
            )
            .toList(),
        'slides': d.slides
            .map(
              (s) => {
                'id': s.id,
                'title': s.title,
                'subtitle': s.subtitle,
                'image_url': s.imageUrl,
                'premium': s.premium,
                'active': s.active,
                'sort_order': s.sortOrder,
              },
            )
            .toList(),
      };

  /// Registers device on server. Omits generic placeholder names so admin renames are kept.
  /// Saves FCM token for this device so admin pushes stay deliverable after long idle periods.
  Future<void> registerFcmToken({
    required String deviceId,
    required String fcmToken,
  }) async {
    final id = deviceId.trim();
    final token = fcmToken.trim();
    if (id.isEmpty || token.isEmpty) return;

    final uri = Uri.parse('$baseUrl/api/v1/public/push/register');
    final res = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_id': id,
            'fcm_token': token,
            'platform': defaultTargetPlatform.name,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('FCM register failed: ${res.statusCode}');
    }
  }

  Future<void> syncViewer({
    required String deviceId,
    String? name,
    String? phone,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/public/users/sync');
    final body = <String, dynamic>{'device_id': deviceId};
    final n = name?.trim() ?? '';
    if (n.isNotEmpty && !isGenericViewerName(n)) body['name'] = n;
    final p = phone?.trim() ?? '';
    if (p.isNotEmpty) body['phone'] = p;

    final res = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Viewer sync failed: ${res.statusCode}');
    }
  }

  Future<void> recordCompletedTransaction({
    required String deviceId,
    required String userName,
    String? phone,
    required double amount,
    required String method,
    required String planKey,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/public/transactions/complete');
    final providerRef = 'APP-${DateTime.now().millisecondsSinceEpoch}';
    final res = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_id': deviceId,
            'user_name': userName,
            'phone': phone ?? '',
            'amount': amount,
            'method': method,
            'plan_key': planKey,
            'provider': 'mobile',
            'provider_ref': providerRef,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 403) {
      throw Exception('Malipo ya majaribio yanapatikana tu ukiendesha app dhidi ya seva ya localhost.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Transaction save failed: ${res.statusCode}');
    }
  }

  int _channelNumericId(Object? value) {
    if (value is int) return value;
    final s = value?.toString() ?? '';
    final digits = s.replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty) return int.tryParse(digits) ?? s.hashCode;
    return s.hashCode;
  }
}
