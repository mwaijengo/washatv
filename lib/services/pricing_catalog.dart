import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../admin/admin_currency.dart';
import '../models/plan.dart';

const String kPricingStorageKey = 'washatvPricing';

/// Order matches subscription tutorial (wiki → mwezi → miezi 3).
const List<String> kPlanIdsOrdered = ['weekly', 'gold', 'platinum'];

/// Swahili line shown under the plan name (same rhythm as the subscription UI).
String planPeriodSubtitle(int days) {
  if (days <= 0) return 'Muda';
  if (days <= 10) return 'Kwa wiki 1';
  if (days <= 35) return 'Kwa mwezi 1';
  if (days <= 100) return 'Kwa miezi 3';
  return 'Siku $days';
}

/// Fallback when SharedPreferences has nothing yet (aligned with admin defaults).
List<Plan> defaultUserPlans() {
  return [
    Plan(id: 'weekly', name: 'WEEKLY', price: fmtTzs(12000), subtitle: planPeriodSubtitle(7), days: 7),
    Plan(id: 'gold', name: 'DHAHABU', price: fmtTzs(25000), subtitle: planPeriodSubtitle(30), days: 30),
    Plan(id: 'platinum', name: 'PLATINUM', price: fmtTzs(85000), subtitle: planPeriodSubtitle(90), days: 90),
  ];
}

/// Loads admin-saved pricing from the same key the admin dashboard writes.
Future<List<Plan>> loadUserPlans() async {
  final defaults = defaultUserPlans();
  try {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(kPricingStorageKey);
    if (raw == null || raw.isEmpty) return defaults;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final out = <Plan>[];
    for (final id in kPlanIdsOrdered) {
      final e = map[id];
      if (e is! Map<String, dynamic>) continue;
      final enabled = e['enabled'] as bool? ?? true;
      if (!enabled) continue;
      final name = (e['name'] as String?)?.trim();
      final price = (e['price'] as num?)?.toDouble();
      final days = (e['duration'] as num?)?.toInt();
      if (name == null || name.isEmpty || price == null || days == null) continue;
      out.add(
        Plan(
          id: id,
          name: name.split('(').first.trim(),
          price: fmtTzs(price),
          subtitle: planPeriodSubtitle(days),
          days: days,
        ),
      );
    }
    return out.isEmpty ? defaults : out;
  } catch (_) {
    return defaults;
  }
}
