import 'dart:convert';

import 'package:http/http.dart' as http;

import 'payment_config.dart';

/// SonicPesa payment flow via Washa API (keys stay on server).
class SonicpesaPaymentService {
  SonicpesaPaymentService({String? apiBase})
      : baseUrl = (apiBase ??
                const String.fromEnvironment(
                  'WASHA_API_BASE_URL',
                  defaultValue: 'https://washatv-production.up.railway.app',
                ))
            .replaceAll(RegExp(r'/+$'), '');

  final String baseUrl;

  Future<SonicpesaInitiateResult> initiate({
    required String deviceId,
    required String userName,
    required String phone,
    required String planKey,
    bool forceNew = false,
  }) async {
    final localPhone = PaymentConfig.normalizeTzLocalPhone(phone) ?? phone.trim();
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/public/payments/sonicpesa/initiate'),
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({
            'device_id': deviceId,
            'user_name': userName,
            'phone': localPhone,
            'plan_key': planKey,
            if (forceNew) 'force_new': true,
          }),
        )
        .timeout(const Duration(seconds: 35));

    final map = _decode(res);
    final orderIdFromBody = (map['order_id'] as String?)?.trim() ?? '';
    final retrySafe = map['retry_safe'] != false;
    final cooldownSeconds = (map['cooldown_seconds'] as num?)?.toInt();

    // DB persist may fail after SonicPesa creates the order — still continue with order_id.
    if ((res.statusCode == 502 || res.statusCode == 500) && orderIdFromBody.isNotEmpty) {
      return SonicpesaInitiateResult(
        orderId: orderIdFromBody,
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        message: (map['message'] as String?)?.trim() ??
            'Angalia simu yako na thibitisha malipo.',
        reused: map['reused'] == true,
        completed: map['completed'] == true,
        premiumUntil: _parsePremiumUntil(map['premium_until']),
      );
    }

    if (res.statusCode == 500) {
      throw SonicpesaPaymentException(
        _userFacingMessage(map, res.statusCode, fallback: 'Seva ya malipo ina hitilafu. Jaribu tena baada ya dakika moja.'),
        statusCode: res.statusCode,
        paymentReceived: map['payment_received'] == true,
        retrySafe: map['retry_safe'] != true ? false : retrySafe,
        cooldownSeconds: cooldownSeconds,
        orderId: orderIdFromBody.isEmpty ? null : orderIdFromBody,
      );
    }
    if (res.statusCode == 502) {
      throw SonicpesaPaymentException(
        _userFacingMessage(
          map,
          res.statusCode,
          fallback: 'Malipo yameanzishwa lakini hayajakamilika kwenye programu. Angalia simu yako.',
        ),
        statusCode: res.statusCode,
        retrySafe: retrySafe,
        cooldownSeconds: cooldownSeconds,
        orderId: orderIdFromBody.isEmpty ? null : orderIdFromBody,
      );
    }
    if (res.statusCode == 503) {
      throw SonicpesaPaymentException(
        _userFacingMessage(
          map,
          res.statusCode,
          fallback: 'Seva ya malipo haipatikani kwa sasa. Jaribu tena baada ya dakika moja.',
        ),
        statusCode: res.statusCode,
        retrySafe: retrySafe,
        cooldownSeconds: cooldownSeconds ?? 120,
        orderId: orderIdFromBody.isEmpty ? null : orderIdFromBody,
      );
    }
    if (res.statusCode == 403) {
      throw SonicpesaPaymentException(
        _userFacingMessage(map, res.statusCode, fallback: 'Usajili wa premium umezimwa kwa sasa.'),
        statusCode: res.statusCode,
        retrySafe: false,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SonicpesaPaymentException(
        _userFacingMessage(map, res.statusCode, fallback: 'Imeshindikana kuanzisha malipo. Jaribu tena.'),
        statusCode: res.statusCode,
        retrySafe: retrySafe,
        cooldownSeconds: cooldownSeconds,
        orderId: orderIdFromBody.isEmpty ? null : orderIdFromBody,
      );
    }
    final orderId = orderIdFromBody;
    if (orderId.isEmpty) {
      throw SonicpesaPaymentException(
        _userFacingMessage(map, res.statusCode, fallback: 'Imeshindikana kuanzisha malipo. Jaribu tena.'),
      );
    }
    return SonicpesaInitiateResult(
      orderId: orderId,
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      message: (map['message'] as String?)?.trim() ??
          'Angalia simu yako na thibitisha malipo ya M-Pesa.',
      reused: map['reused'] == true,
      completed: map['completed'] == true,
      premiumUntil: _parsePremiumUntil(map['premium_until']),
    );
  }

  Future<SonicpesaStatusResult> checkStatus({
    required String deviceId,
    required String orderId,
    String? userName,
    String? phone,
    String? planKey,
    int? amount,
  }) async {
    final localPhone = phone != null && phone.isNotEmpty
        ? (PaymentConfig.normalizeTzLocalPhone(phone) ?? phone.trim())
        : null;
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/public/payments/sonicpesa/status'),
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({
            'device_id': deviceId,
            'order_id': orderId,
            if (userName != null && userName.isNotEmpty) 'user_name': userName,
            if (localPhone != null && localPhone.isNotEmpty) 'phone': localPhone,
            if (planKey != null && planKey.isNotEmpty) 'plan_key': planKey,
            if (amount != null && amount > 0) 'amount': amount,
          }),
        )
        .timeout(const Duration(seconds: 25));

    final map = _decode(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final paymentReceived = map['payment_received'] == true;
      throw SonicpesaPaymentException(
        _userFacingMessage(map, res.statusCode, fallback: 'Imeshindikana kuangalia hali ya malipo.'),
        statusCode: res.statusCode,
        paymentReceived: paymentReceived,
        retrySafe: map['retry_safe'] != false && !paymentReceived,
        orderId: (map['order_id'] as String?)?.trim(),
      );
    }

    final status = (map['payment_status'] as String?)?.trim().toUpperCase() ?? 'PENDING';
    final completed = map['completed'] == true;
    final failed = map['failed'] == true;
    final premiumUntil = _parsePremiumUntil(map['premium_until']);

    return SonicpesaStatusResult(
      paymentStatus: status,
      completed: completed,
      failed: failed,
      pending: map['pending'] == true || (!completed && !failed),
      premiumUntil: premiumUntil,
      message: (map['message'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> _decode(http.Response res) {
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {'error': res.body};
    }
  }

  String _userFacingMessage(Map<String, dynamic> map, int? statusCode, {required String fallback}) {
    final raw = _rawServerMessage(map);
    if (raw == null) {
      if (statusCode == 500 || statusCode == 502 || statusCode == 503 || statusCode == 504) {
        return 'Seva ya malipo haipatikani kwa sasa. Jaribu tena baada ya dakika moja.';
      }
      return fallback;
    }
    final lower = raw.toLowerCase();
    if (lower.contains('internal server error') ||
        lower.contains('fetch failed') ||
        lower.contains('unreachable') ||
        lower.contains('timed out')) {
      return 'Seva ya malipo haipatikani kwa sasa. Jaribu tena baada ya dakika moja.';
    }
    if (lower.contains('angalia simu')) {
      return raw;
    }
    if (lower.contains('order_id') || lower.contains('sonicpesa')) {
      return 'Imeshindikana kuanzisha malipo. Hakikisha namba ya simu ni sahihi na jaribu tena.';
    }
    if (lower.contains('not configured')) {
      return 'Malipo hayajasanidi kwenye seva. Wasiliana na msaada.';
    }
    if (lower.contains('device_id') || lower.contains('plan_key')) {
      return 'Taarifa za malipo hazikamilika. Funga na fungua programu, kisha jaribu tena.';
    }
    if (lower.contains('phone') || lower.contains('tanzanian') || lower.contains('10 digits')) {
      return 'Weka namba ya simu sahihi: 07…, 06… (Halotel 061/062/063/069), au 255…';
    }
    if (lower.contains('subscription') && lower.contains('disabled')) {
      return 'Usajili wa premium umezimwa kwa sasa.';
    }
    if (lower.contains('plan not found') || lower.contains('not available')) {
      return 'Mpango uliyochagua haupatikani. Chagua mpango mwingine.';
    }
    // Hide raw HTTP codes / English API dumps from the payment UI.
    if (RegExp(r'\b(4\d{2}|5\d{2})\b').hasMatch(raw) || raw.length > 120) {
      return fallback;
    }
    return raw;
  }

  String? _rawServerMessage(Map<String, dynamic> map) {
    for (final key in ['error', 'message']) {
      final v = map[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  DateTime? _parsePremiumUntil(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final ms = int.tryParse(s);
    if (ms != null && ms > 100000000000) return DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime.tryParse(s);
  }
}

class SonicpesaInitiateResult {
  const SonicpesaInitiateResult({
    required this.orderId,
    required this.amount,
    required this.message,
    this.reused = false,
    this.completed = false,
    this.premiumUntil,
  });

  final String orderId;
  final int amount;
  final String message;
  final bool reused;
  final bool completed;
  final DateTime? premiumUntil;
}

class SonicpesaStatusResult {
  const SonicpesaStatusResult({
    required this.paymentStatus,
    required this.completed,
    required this.failed,
    required this.pending,
    this.premiumUntil,
    this.message,
  });

  final String paymentStatus;
  final bool completed;
  final bool failed;
  final bool pending;
  final DateTime? premiumUntil;
  final String? message;
}

class SonicpesaPaymentException implements Exception {
  SonicpesaPaymentException(
    this.message, {
    this.statusCode,
    this.paymentReceived = false,
    this.retrySafe = true,
    this.cooldownSeconds,
    this.orderId,
  });

  final String message;
  final int? statusCode;
  final bool paymentReceived;
  /// False when creating another STK push could double-charge the user.
  final bool retrySafe;
  final int? cooldownSeconds;
  final String? orderId;

  @override
  String toString() => message;
}
