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
}
