import 'dart:math';

import 'admin_models.dart';

Map<String, PricingPlan> defaultPricingPlans() {
  return {
    'gold': PricingPlan(
      name: 'DHAHABU',
      originalPrice: 25000,
      price: 25000,
      discount: 0,
      duration: 30,
      features: const [],
      popular: true,
      enabled: true,
      colorKey: 'amber',
    ),
    'platinum': PricingPlan(
      name: 'PLATINUM',
      originalPrice: 85000,
      price: 85000,
      discount: 0,
      duration: 90,
      features: const [],
      popular: false,
      enabled: true,
      colorKey: 'purple',
    ),
    'weekly': PricingPlan(
      name: 'WEEKLY',
      originalPrice: 12000,
      price: 12000,
      discount: 0,
      duration: 7,
      features: const [],
      popular: false,
      enabled: true,
      colorKey: 'blue',
    ),
  };
}

/// Same shape as [StorageService.getOrCreateDeviceId] in the user app.
String _mockDeviceId(Random rand) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  String ch() => chars[rand.nextInt(chars.length)];
  return 'WTV-${ch()}${ch()}${ch()}${ch()}-${ch()}${ch()}${ch()}${ch()}';
}

List<AdminUser> generateUsers(Random rand) {
  return <AdminUser>[];
}

List<AdminChannel> generateChannels(Random rand) {
  return <AdminChannel>[];
}

List<AdminSlide> generateSlides() {
  return [
    AdminSlide(
      id: 'SL-001',
      title: 'UEFA Champions League',
      subtitle: 'Fainali · Real Madrid vs Barcelona',
      imageUrl: 'https://images.unsplash.com/photo-1517649763962-0c623066013b?q=80&w=1470',
      premium: true,
      active: true,
      sortOrder: 1,
    ),
    AdminSlide(
      id: 'SL-002',
      title: 'Stranger Things',
      subtitle: 'Msimu 5 · Sasa Inastreami',
      imageUrl: 'https://images.unsplash.com/photo-1615986201152-7686a4867f30?q=80&w=1470',
      premium: false,
      active: true,
      sortOrder: 2,
    ),
    AdminSlide(
      id: 'SL-003',
      title: 'Dune: Unabii',
      subtitle: 'Onyesho la Kipekee',
      imageUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=1374',
      premium: true,
      active: true,
      sortOrder: 3,
    ),
    AdminSlide(
      id: 'SL-004',
      title: 'NBA Fainali',
      subtitle: 'Lakers vs Celtics',
      imageUrl: 'https://images.unsplash.com/photo-1504450758481-7338eba7524a?q=80&w=1469',
      premium: false,
      active: true,
      sortOrder: 4,
    ),
  ];
}

List<AdminSubscription> generateSubscriptions(
  Random rand,
  List<AdminUser> users,
  Map<String, PricingPlan> pricing,
) {
  return <AdminSubscription>[];
}

List<AdminPayment> generatePayments(Random rand, List<AdminUser> users) {
  return <AdminPayment>[];
}

List<AdminNotification> staticNotifications() {
  return <AdminNotification>[];
}

List<AdminLog> generateLogs(Random rand) {
  return <AdminLog>[];
}
