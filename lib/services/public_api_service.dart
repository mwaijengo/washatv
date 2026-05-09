import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../admin/admin_currency.dart';
import '../models/channel.dart';
import '../models/hero_slide.dart';
import '../models/plan.dart';
import 'pricing_catalog.dart';

class PublicBootstrapData {
  PublicBootstrapData({
    required this.version,
    required this.channels,
    required this.slides,
    required this.plans,
    required this.whatsappNumber,
  });

  final int version;
  final List<Channel> channels;
  final List<HeroSlide> slides;
  final List<Plan> plans;
  final String whatsappNumber;
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

int _parseConfigVersionJson(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw.trim()) ?? 0;
  return 0;
}

class PublicApiService {
  /// [baseUrl] defaults to the Washa API on Railway unless `--dart-define=WASHA_API_BASE_URL=...` overrides it (e.g. local backend).
  PublicApiService({String? baseUrl})
      : baseUrl = (baseUrl ?? const String.fromEnvironment('WASHA_API_BASE_URL', defaultValue: 'https://washatv-production.up.railway.app')).replaceAll(RegExp(r'/+$'), '');

  final String baseUrl;

  Future<PublicBootstrapData> fetchBootstrap() async {
    final uri = Uri.parse('$baseUrl/api/v1/public/bootstrap');
    final res = await http.get(uri, headers: _publicGetHeaders).timeout(const Duration(seconds: 30));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Bootstrap failed: ${res.statusCode}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final settings = (map['settings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    final rawPlans = (map['plans'] as List?)?.cast<dynamic>() ?? const [];
    final rawChannels = (map['channels'] as List?)?.cast<dynamic>() ?? const [];
    final rawSlides = (map['slides'] as List?)?.cast<dynamic>() ?? const [];

    final plans = <Plan>[];
    for (final item in rawPlans) {
      if (item is! Map) continue;
      final j = item.cast<String, dynamic>();
      final enabled = j['enabled'] as bool? ?? true;
      if (!enabled) continue;
      final id = (j['plan_key'] as String?)?.trim();
      final name = (j['name'] as String?)?.trim();
      final price = (j['price'] as num?)?.toDouble();
      final days = (j['duration_days'] as num?)?.toInt();
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
      channels.add(
        Channel(
          id: _channelNumericId(j['id']),
          name: name,
          premium: j['premium'] as bool? ?? false,
          imageUrl: thumb,
          live: j['live'] as bool? ?? false,
          category: category,
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
      channels: channels,
      slides: slides,
      plans: plans,
      whatsappNumber: (settings['whatsapp_number'] as String?)?.trim() ?? '',
    );
  }

  Future<int> fetchConfigVersion() async {
    final uri = Uri.parse('$baseUrl/api/v1/public/config');
    final res = await http.get(uri, headers: _publicGetHeaders).timeout(const Duration(seconds: 25));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Config fetch failed: ${res.statusCode}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    return _parseConfigVersionJson(map['version']);
  }

  Future<void> syncViewer({
    required String deviceId,
    required String name,
    String? phone,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/public/users/sync');
    final res = await http
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'device_id': deviceId,
            'name': name,
            'phone': phone ?? '',
          }),
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
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Transaction save failed: ${res.statusCode}');
    }
  }

  int _channelNumericId(Object? value) {
    if (value is int) return value;
    final s = value?.toString() ?? '';
    final digits = s.replaceAll(RegExp(r'\\D'), '');
    if (digits.isNotEmpty) return int.tryParse(digits) ?? s.hashCode;
    return s.hashCode;
  }
}
