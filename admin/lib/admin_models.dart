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

  bool get adminAccessActive =>
      adminAccessUntil != null && adminAccessUntil!.isAfter(DateTime.now());

  /// Matches viewer API premium logic (real future expiry only — never NULL forever).
  bool get effectivePremium {
    final now = DateTime.now();
    if (adminAccessActive) return true;
    if (premiumUntil != null && premiumUntil!.isAfter(now)) return true;
    return false;
  }

  /// Safe for UI / clipboard — never null after hot reload.
  String get displayDeviceId {
    final v = deviceId;
    if (v != null && v.isNotEmpty) return v;
    final tail = id.replaceAll(RegExp(r'\D'), '');
    final pad = tail.length >= 4
        ? tail.substring(tail.length - 4)
        : tail.padLeft(4, '0');
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
    this.drmClearKey = '',
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

  /// ClearKey payload when [effectiveDrm] is `clearkey` (hex kid:key, JSON, etc.).
  String drmClearKey;

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
    this.phone = '',
    this.provider = '',
    this.verifiedAt,
    this.remoteStatus,
  });
  final String id;
  final String userName;
  final double amount;
  final String method;
  String status;
  final String transactionId;
  final DateTime createdAt;
  final String? planKey;
  final String phone;
  final String provider;

  /// Last time the order was checked against SonicPesa (by the server or an admin).
  DateTime? verifiedAt;

  /// Status SonicPesa reported on that check (SUCCESS / PENDING / FAILED …).
  String? remoteStatus;

  bool get isSonicpesa =>
      provider == 'sonicpesa' || transactionId.startsWith('sp_');
}

class AdminNotification {
  AdminNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.read,
    required this.createdAt,
    this.target = 'all',
    this.delivery = 'sent',
    this.sentCount = 0,
    this.failedCount = 0,
    this.error,
  });
  final String id;
  final String title;
  final String message;
  final String type;
  final bool read;
  final DateTime createdAt;

  /// `all`, `premium`, `free`, `user:<deviceId>` or `reminder:<audience>:<source>`.
  final String target;

  /// `sent`, `bridge`, `failed` or `not_configured`.
  final String delivery;
  final int sentCount;
  final int failedCount;
  final String? error;
}

/// A user who should receive a subscription reminder.
class ReminderUser {
  ReminderUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.deviceId,
    required this.endsAt,
    required this.remindedAt,
  });
  final String id;
  final String name;
  final String phone;
  final String deviceId;
  final DateTime? endsAt;
  final DateTime? remindedAt;
}

class ReminderSummary {
  const ReminderSummary({
    this.days = 3,
    this.expiring = 0,
    this.expiringUnsent = 0,
    this.expired = 0,
    this.expiredUnsent = 0,
    this.pushConfigured = true,
    this.autoReminders = true,
    this.expiringTitle = '',
    this.expiringBody = '',
    this.expiredTitle = '',
    this.expiredBody = '',
  });
  final int days;
  final int expiring;
  final int expiringUnsent;
  final int expired;
  final int expiredUnsent;
  final bool pushConfigured;
  final bool autoReminders;
  final String expiringTitle;
  final String expiringBody;
  final String expiredTitle;
  final String expiredBody;
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
    this.live = const AdminLiveStats(),
    this.days14 = const [],
    this.recentPayments = const [],
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
  final AdminLiveStats live;

  /// Last 14 Tanzania days, oldest first.
  final List<AdminDayStat> days14;
  final List<AdminRecentPayment> recentPayments;
}

/// Right-now activity from `stats.live`.
class AdminLiveStats {
  const AdminLiveStats({
    this.onlineNow = 0,
    this.activeToday = 0,
    this.active7d = 0,
    this.newUsersToday = 0,
    this.pendingPayments = 0,
    this.failedToday = 0,
    this.revenue7d = 0,
    this.revenue30d = 0,
  });
  final int onlineNow;
  final int activeToday;
  final int active7d;
  final int newUsersToday;
  final int pendingPayments;
  final int failedToday;
  final double revenue7d;
  final double revenue30d;
}

class AdminDayStat {
  const AdminDayStat({
    required this.day,
    required this.registrations,
    required this.purchases,
    required this.revenue,
  });
  final DateTime day;
  final int registrations;
  final int purchases;
  final double revenue;
}

class AdminRecentPayment {
  const AdminRecentPayment({
    required this.id,
    required this.orderId,
    required this.userName,
    required this.amount,
    required this.planKey,
    required this.status,
    required this.at,
  });
  final String id;
  final String? orderId;
  final String userName;
  final double amount;
  final String? planKey;
  final String status;
  final DateTime at;
}

class AdminSettings {
  String siteName = 'WASHA TV';
  bool subscriptionEnabled = true;
  bool maintenanceMode = false;

  /// E.164-style or local digits; shown on user Profile → WhatsApp.
  String whatsappNumber = '';

  /// Force Play Store update (Supasoka-style).
  bool forceUpdateEnabled = false;
  int minAndroidBuild = 0;
  String minAndroidVersion = '';
  String latestAndroidVersion = '';
  int latestAndroidBuild = 0;
  String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.washatv';
  String updateTitle = 'Sasisha WASHA TV';
  String updateMessage =
      'Toleo jipya linahitajika ili kuendelea kutumia app. Pakua kutoka Play Store kisha fungua tena.';
}
