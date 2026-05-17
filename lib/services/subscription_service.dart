import '../models/plan.dart';
import 'payment_config.dart';

class SubscriptionService {
  DateTime calculateEndDate(Plan plan) {
    return DateTime.now().add(Duration(days: plan.days));
  }

  bool isPremium(DateTime? endDate) {
    if (endDate == null) return false;
    return endDate.isAfter(DateTime.now());
  }

  /// Prefer the later expiry when merging local payment with server grants.
  DateTime? mergeEndDates(DateTime? local, DateTime? remote) {
    if (local == null) return remote;
    if (remote == null) return local;
    return local.isAfter(remote) ? local : remote;
  }

  /// Normalized local `0XXXXXXXXX` for forms + API (Halotel `061`–`069`, `07…`, `255…`).
  String normalizeTzPhone(String raw) {
    return PaymentConfig.normalizeTzLocalPhone(raw) ?? raw.trim();
  }

  /// ISO-8601 string or epoch ms from payment / user-premium APIs.
  DateTime? parsePremiumUntil(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
    if (raw is num) return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final asInt = int.tryParse(s);
    if (asInt != null && asInt > 1e11) return DateTime.fromMillisecondsSinceEpoch(asInt);
    return DateTime.tryParse(s);
  }
}
