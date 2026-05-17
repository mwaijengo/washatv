class AdminUser {
  AdminUser({
    required this.id,
    required this.name,
    required this.phone,
    this.deviceId,
    required this.status,
    required this.subscription,
    required this.createdAt,
    this.premiumUntil,
    this.adminAccessUntil,
  });
  final String id;
  String name;
  final String phone;
  /// Matches client app `StorageService` format (e.g. WTV-AB12-CD34).
  /// Nullable defensively: web hot reload can leave stale instances without this field.
  final String? deviceId;
  String status;
  String subscription;
  final DateTime createdAt;

  /// Paid premium window from transactions (server `premium_until`).
  DateTime? premiumUntil;

  /// Extra premium window granted from admin (extends smartly when stacked).
  DateTime? adminAccessUntil;

  bool get adminAccessActive => adminAccessUntil != null && adminAccessUntil!.isAfter(DateTime.now());

  /// Matches viewer API premium logic (subscription + dates).
  bool get effectivePremium {
    final now = DateTime.now();
    if (adminAccessActive) return true;
    if (premiumUntil != null && premiumUntil!.isAfter(now)) return true;
    if (subscription == 'premium') {
      // Legacy rows without premium_until — treat as active.
      return premiumUntil == null;
    }
    return false;
  }

  /// Safe for UI / clipboard — never null after hot reload.
  String get displayDeviceId {
    final v = deviceId;
    if (v != null && v.isNotEmpty) return v;
    final tail = id.replaceAll(RegExp(r'\D'), '');
    final pad = tail.length >= 4 ? tail.substring(tail.length - 4) : tail.padLeft(4, '0');
    return 'WTV-$pad-FALL';
  }
}

class AdminChannel {
  AdminChannel({
    required this.id,
    required this.name,
    required this.category,
    required this.premium,
    required this.live,
    required this.status,
    required this.thumbnail,
    this.streamUrl = '',
    required this.viewers,
    required this.rating,
    this.drm,
  });
  final String id;
  String name;
  String category;
  bool premium;
  bool live;
  /// `active` or `inactive` — inactive channels can be hidden from the viewer app when wired to API.
  String status;
  String thumbnail;
  /// HLS / m3u8 / mp4 playback URL for the viewer player.
  String streamUrl;
  int viewers;
  String rating;
  /// `none` | `clearkey` | `widevine` — nullable so web hot reload does not leave stale null under non-null `String`.
  String? drm;

  String get effectiveDrm {
    final v = drm;
    if (v != null && v.isNotEmpty) return v;
    return 'none';
  }
}

class AdminSlide {
  AdminSlide({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.premium,
    required this.active,
    required this.sortOrder,
  });
  final String id;
  String title;
  String subtitle;
  String imageUrl;
  bool premium;
  bool active;
  int sortOrder;
}

class AdminSubscription {
  AdminSubscription({
    required this.id,
    required this.userName,
    required this.plan,
    required this.price,
    required this.endDate,
    required this.status,
  });
  final String id;
  final String userName;
  final String plan;
  final double price;
  final DateTime endDate;
  final String status;
}

class AdminPayment {
  AdminPayment({
    required this.id,
    required this.userName,
    required this.amount,
    required this.method,
    required this.status,
    required this.transactionId,
    required this.createdAt,
    this.planKey,
  });
  final String id;
  final String userName;
  final double amount;
  final String method;
  String status;
  final String transactionId;
  final DateTime createdAt;
  final String? planKey;
}

class AdminNotification {
  AdminNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.read,
    required this.createdAt,
  });
  final String id;
  final String title;
  final String message;
  final String type;
  final bool read;
  final DateTime createdAt;
}

class AdminLog {
  AdminLog({
    required this.id,
    required this.adminName,
    required this.action,
    required this.details,
    required this.createdAt,
  });
  final String id;
  final String adminName;
  final String action;
  final String details;
  final DateTime createdAt;
}

class PricingPlan {
  PricingPlan({
    required this.name,
    required this.originalPrice,
    required this.price,
    required this.discount,
    required this.duration,
    required this.features,
    required this.popular,
    required this.enabled,
    required this.colorKey,
  });
  String name;
  double originalPrice;
  double price;
  int discount;
  int duration;
  List<String> features;
  bool popular;
  bool enabled;
  final String colorKey; // amber, purple, blue
}

/// Live dashboard metrics from `GET /api/v1/admin/stats/overview`.
class AdminDashboardStats {
  AdminDashboardStats({
    required this.totalUsers,
    required this.premiumUsers,
    required this.freeUsers,
    required this.activeChannels,
    required this.revenue,
    required this.monthLabels,
    required this.newUsersPerMonth,
    required this.premiumPurchasesPerMonth,
    required this.revenuePerMonth,
    required this.dailyLabels,
    required this.dailyRegistrations,
    required this.planWeekly,
    required this.planGold,
    required this.planPlatinum,
    required this.planOther,
  });

  final int totalUsers;
  final int premiumUsers;
  final int freeUsers;
  final int activeChannels;
  final double revenue;
  final List<String> monthLabels;
  final List<double> newUsersPerMonth;
  final List<double> premiumPurchasesPerMonth;
  final List<double> revenuePerMonth;
  final List<String> dailyLabels;
  final List<double> dailyRegistrations;
  final int planWeekly;
  final int planGold;
  final int planPlatinum;
  final int planOther;
}

class AdminSettings {
  String siteName = 'WASHA TV';
  bool subscriptionEnabled = true;
  bool maintenanceMode = false;
  /// E.164-style or local digits; shown on user Profile → WhatsApp.
  String whatsappNumber = '';
}
