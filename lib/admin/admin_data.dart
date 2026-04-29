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
  const names = ['Anne Ayoub', 'John Doe', 'Maria Santos', 'Ahmed Hassan', 'Priya Patel'];
  return List.generate(50, (i) {
    final ni = i % 5;
    return AdminUser(
      id: 'USR-${(i + 1).toString().padLeft(4, '0')}',
      name: i < 5 ? names[ni] : 'User ${i + 1}',
      phone: '+2557${(10000000 + rand.nextInt(90000000))}',
      deviceId: _mockDeviceId(rand),
      status: rand.nextDouble() > 0.85 ? 'suspended' : 'active',
      subscription: rand.nextDouble() > 0.55 ? 'premium' : 'free',
      createdAt: DateTime.now().subtract(Duration(days: rand.nextInt(90))),
      adminAccessUntil: i % 11 == 0 ? DateTime.now().add(Duration(hours: rand.nextInt(48) + 1)) : null,
    );
  });
}

List<AdminChannel> generateChannels(Random rand) {
  const names = [
    'ESPN Ultra HD',
    'Sky Sports News',
    'Fox Sports',
    'NBA TV',
    'NFL Network',
    'HBO Max',
    'Paramount Pictures',
    'Showtime',
    'Starz Cinema',
    'CNN International',
  ];
  const cats = ['Sports', 'Sports', 'Sports', 'Sports', 'Sports', 'Movies', 'Movies', 'Movies', 'Movies', 'News'];
  return List.generate(42, (i) {
    final idx = i % 10;
    final suffix = i >= 10 ? ' ${(i ~/ 10) + 1}' : '';
    return AdminChannel(
      id: 'CH-${(i + 1).toString().padLeft(4, '0')}',
      name: '${names[idx]}$suffix',
      category: cats[idx],
      premium: i < 38,
      live: i % 3 != 0,
      status: 'active',
      thumbnail: 'https://picsum.photos/seed/ch$i/400/225',
      viewers: rand.nextInt(5000) + 100,
      rating: (rand.nextDouble() * 2 + 3).toStringAsFixed(1),
      drm: ['none', 'clearkey', 'widevine'][i % 3],
    );
  });
}

List<AdminSubscription> generateSubscriptions(
  Random rand,
  List<AdminUser> users,
  Map<String, PricingPlan> pricing,
) {
  const plans = ['gold', 'platinum', 'weekly'];
  const durations = {'gold': 30, 'platinum': 90, 'weekly': 7};
  return List.generate(30, (i) {
    final plan = plans[i % 3];
    final start = DateTime.now().subtract(Duration(days: rand.nextInt(60)));
    final end = start.add(Duration(days: durations[plan]!));
    return AdminSubscription(
      id: 'SUB-${(i + 1).toString().padLeft(4, '0')}',
      userName: users[i].name,
      plan: plan,
      price: pricing[plan]!.price,
      endDate: end,
      status: end.isAfter(DateTime.now()) ? 'active' : 'expired',
    );
  });
}

List<AdminPayment> generatePayments(Random rand, List<AdminUser> users) {
  // Completed payments are confirmed automatically — no manual approval in UI.
  const statuses = ['completed', 'completed', 'completed', 'completed', 'failed'];
  return List.generate(56, (i) {
    return AdminPayment(
      id: 'PAY-${(i + 1).toString().padLeft(4, '0')}',
      userName: users[i % users.length].name,
      amount: [25000.0, 85000.0, 12000.0][i % 3],
      method: 'M-Pesa',
      status: statuses[i % statuses.length],
      transactionId: 'MP${rand.nextInt(0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}',
      createdAt: DateTime.now().subtract(Duration(days: rand.nextInt(30))),
    );
  });
}

List<AdminNotification> staticNotifications() {
  final now = DateTime.now();
  return [
    AdminNotification(
      id: 'NOT-001',
      title: 'New User',
      message: 'Anne Ayoub registered',
      type: 'info',
      read: false,
      createdAt: now.subtract(const Duration(minutes: 5)),
    ),
    AdminNotification(
      id: 'NOT-002',
      title: 'Payment',
      message: 'TSh 25,000 DHAHABU (GOLD) subscription',
      type: 'success',
      read: false,
      createdAt: now.subtract(const Duration(minutes: 15)),
    ),
    AdminNotification(
      id: 'NOT-003',
      title: 'Offline',
      message: 'ESPN Ultra HD disconnected',
      type: 'warning',
      read: true,
      createdAt: now.subtract(const Duration(hours: 1)),
    ),
  ];
}

List<AdminLog> generateLogs(Random rand) {
  const actions = ['Login', 'Channel Added', 'Payment', 'Subscription', 'User Banned', 'Settings'];
  return List.generate(50, (i) {
    return AdminLog(
      id: 'LOG-${(i + 1).toString().padLeft(4, '0')}',
      adminName: 'Super Admin',
      action: actions[i % 6],
      details: 'Action on ${DateTime.now().subtract(Duration(days: rand.nextInt(30))).toLocal().toString().split(' ').first}',
      createdAt: DateTime.now().subtract(Duration(days: rand.nextInt(30))),
    );
  });
}
