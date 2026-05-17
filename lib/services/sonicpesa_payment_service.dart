import 'dart:convert';

import 'package:http/http.dart' as http;

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
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/public/payments/sonicpesa/initiate'),
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({
            'device_id': deviceId,
            'user_name': userName,
            'phone': phone,
            'plan_key': planKey,
          }),
        )
        .timeout(const Duration(seconds: 35));

    final map = _decode(res);
    if (res.statusCode == 503) {
      throw SonicpesaPaymentException(
        'Malipo hayajasanidi kwenye seva. Wasiliana na msaada.',
        statusCode: res.statusCode,
      );
    }
    if (res.statusCode == 403) {
      throw SonicpesaPaymentException(
        _message(map, 'Usajili wa premium umezimwa kwa sasa.'),
        statusCode: res.statusCode,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SonicpesaPaymentException(
        _message(map, 'Imeshindikana kuanzisha malipo (${res.statusCode})'),
        statusCode: res.statusCode,
      );
    }
    final orderId = (map['order_id'] as String?)?.trim() ?? '';
    if (orderId.isEmpty) {
      throw SonicpesaPaymentException('Hakuna order_id kutoka kwa SonicPesa.');
    }
    return SonicpesaInitiateResult(
      orderId: orderId,
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      message: (map['message'] as String?)?.trim() ??
          'Angalia simu yako na thibitisha malipo ya M-Pesa.',
    );
  }

  Future<SonicpesaStatusResult> checkStatus({
    required String deviceId,
    required String orderId,
    String? userName,
    String? phone,
  }) async {
    final res = await http
        .post(
          Uri.parse('$baseUrl/api/v1/public/payments/sonicpesa/status'),
          headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: jsonEncode({
            'device_id': deviceId,
            'order_id': orderId,
            if (userName != null && userName.isNotEmpty) 'user_name': userName,
            if (phone != null && phone.isNotEmpty) 'phone': phone,
          }),
        )
        .timeout(const Duration(seconds: 25));

    final map = _decode(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SonicpesaPaymentException(
        _message(map, 'Imeshindikana kuangalia hali ya malipo'),
        statusCode: res.statusCode,
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

  String _message(Map<String, dynamic> map, String fallback) {
    final e = map['error'];
    if (e is String && e.trim().isNotEmpty) return e.trim();
    return fallback;
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
  });

  final String orderId;
  final int amount;
  final String message;
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
  SonicpesaPaymentException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
