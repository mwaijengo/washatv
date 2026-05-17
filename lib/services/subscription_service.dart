import '../models/plan.dart';

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

  /// `07XXXXXXXX` or `2557XXXXXXXX` → `07XXXXXXXX` for API + display.
  String normalizeTzPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return raw.trim();
    if (digits.startsWith('255') && digits.length >= 12) {
      return '0${digits.substring(3)}';
    }
    if (digits.startsWith('0')) return digits;
    if (digits.length >= 9) return '0$digits';
    return raw.trim();
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
