import '../models/plan.dart';

class SubscriptionService {
  DateTime calculateEndDate(Plan plan) {
    return DateTime.now().add(Duration(days: plan.days));
  }

  bool isPremium(DateTime? endDate) {
    if (endDate == null) return false;
    return endDate.isAfter(DateTime.now());
  }
}
