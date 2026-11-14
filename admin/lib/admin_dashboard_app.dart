import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_auth.dart';
import 'admin_colors.dart';
import 'admin_currency.dart';
import 'admin_data.dart';
import 'admin_models.dart';
import 'admin_prefs_keys.dart';
import 'admin_ui.dart';
import 'channel_categories.dart';

/// Off-main-isolate JSON parse for large admin sync payloads (prevents UI freezes).
Map<String, dynamic> _decodeJsonMapIsolate(String body) =>
    jsonDecode(body) as Map<String, dynamic>;

enum _AccessUnit { hours, days, weeks, months }

/// Holds pricing text fields for one admin session (safe across Flutter web hot reload).
class _PricingControllersBundle {
  final Map<String, TextEditingController> name = {};
  final Map<String, TextEditingController> price = {};
  final Map<String, TextEditingController> days = {};

  void dispose() {
    for (final c in name.values) {
      c.dispose();
    }
    for (final c in price.values) {
      c.dispose();
    }
    for (final c in days.values) {
      c.dispose();
    }
    name.clear();
    price.clear();
    days.clear();
  }
}

/// Prefer `cd admin && flutter run` on device (lightweight plugins). See admin/README.md.
class WashaAdminApp extends StatelessWidget {
  const WashaAdminApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    // System fonts only — no GoogleFonts network fetch (avoids startup ANR on device).
    return MaterialApp(
      title: 'Waisa',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: AdminColors.bgPrimary,
        textTheme: base.textTheme.apply(
          bodyColor: AdminColors.textPrimary,
          displayColor: AdminColors.textPrimary,
        ),
        colorScheme: const ColorScheme.dark(
          primary: AdminColors.accentPrimary,
          surface: AdminColors.bgSecondary,
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          },
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AdminColors.bgSecondary,
          surfaceTintColor: Colors.transparent,
          elevation: 24,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0x14FFFFFF)),
          ),
          titleTextStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AdminColors.textPrimary,
          ),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: AdminColors.bgTertiary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x1AFFFFFF)),
          ),
          textStyle: const TextStyle(
            fontSize: 11.5,
            color: AdminColors.textPrimary,
          ),
          waitDuration: const Duration(milliseconds: 400),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(const Color(0x33FFFFFF)),
          radius: const Radius.circular(8),
          thickness: WidgetStateProperty.all(6),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AdminColors.accentPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF818CF8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AdminColors.bgTertiary,
          selectedColor: const Color(0x336366F1),
          side: const BorderSide(color: Color(0x1AFFFFFF)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF818CF8),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0x14FFFFFF),
          space: 1,
        ),
      ),
      home: home,
    );
  }
}

enum AdminPageId {
  dashboard,
  users,
  channels,
  slides,
  subscriptions,
  pricing,
  payments,
  notifications,
  analytics,
  settings,
  logs,
}

class AdminScaffold extends StatefulWidget {
  const AdminScaffold({super.key, required this.auth});

  final AdminAuth auth;

  @override
  State<AdminScaffold> createState() => _AdminScaffoldState();
}

class _AdminScaffoldState extends State<AdminScaffold>
    with WidgetsBindingObserver {
  final _rand = Random();
  final _globalSearch = TextEditingController();
  final _userSearch = TextEditingController();
  final _subsSearch = TextEditingController();
  final _paySearch = TextEditingController();
  int _subsFilter = 0;
  int _payFilter = 0;
  int _analyticsMetric = 0;
  int _historyFilter = 0;
  int _historyShown = 30;
  final Set<String> _verifyingRefs = {};
  bool _bulkVerifying = false;
  Timer? _userSearchDebounce;

  /// Authoritative DB count (may exceed loaded list length when filtered).
  int _usersTotal = 0;

  /// Rows matching the current server search (`q`). 0 when not searching.
  int _usersMatched = 0;
  bool _usersSearchLoading = false;

  /// Index into [_userFilterKeys]; the server filters and counts each bucket.
  int _usersFilter = 0;
  static const _userFilterKeys = [
    'all',
    'premium',
    'expired',
    'free',
    'blocked',
  ];

  /// Which filter the rows in [_users] were loaded with (older servers ignore `filter`).
  String _usersLoadedFilter = 'all';
  Map<String, int>? _userCounts;
  int _usersLimit = _usersBrowseLimit;
  final Set<String> _userBusy = {};

  /// Prevents overlapping full syncs from racing / freezing the UI.
  int _hydrateSeq = 0;
  Future<bool>? _hydrateInFlight;

  /// Browse page size — keep modest; search uses the server `q` path to find any user.
  static const int _usersBrowseLimit = 200;

  /// Pause background polls while the OS reports the app is not visible.
  bool _appLifecyclePaused = false;

  /// Same Railway API as the viewer app unless overridden with `--dart-define=WASHA_API_BASE_URL=...`.
  String get _apiBase => widget.auth.apiBase;
  bool get _hasAdminSession => widget.auth.hasSession;

  late List<AdminUser> _users;
  late List<AdminChannel> _channels;
  late List<AdminSlide> _slides;
  late List<AdminSubscription> _subscriptions;
  late List<AdminPayment> _payments;
  late List<AdminNotification> _notifications;
  late List<AdminLog> _logs;
  late Map<String, PricingPlan> _pricing;
  AdminDashboardStats? _dashboardStats;
  DateTime? _statsFetchedAt;
  bool _statsRefreshFailed = false;
  ReminderSummary? _reminderSummary;
  List<ReminderUser> _expiringUsers = const [];
  List<ReminderUser> _expiredUsers = const [];
  bool _remindersLoading = false;
  String? _remindersError;
  final _settings = AdminSettings();

  /// Field initializers run on first read — survives hot reload when `initState` does not re-run.
  late final TextEditingController _settingsSiteName = TextEditingController(
    text: _settings.siteName,
  );
  late final TextEditingController _settingsWhatsapp = TextEditingController(
    text: _settings.whatsappNumber,
  );
  late final TextEditingController _settingsMinBuild = TextEditingController(
    text: '0',
  );
  late final TextEditingController _settingsMinVersion =
      TextEditingController();
  late final TextEditingController _settingsLatestVersion =
      TextEditingController();
  late final TextEditingController _settingsLatestBuild = TextEditingController(
    text: '0',
  );
  late final TextEditingController _settingsPlayStoreUrl =
      TextEditingController(
        text: 'https://play.google.com/store/apps/details?id=com.washatv',
      );
  late final TextEditingController _settingsUpdateTitle = TextEditingController(
    text: 'Sasisha WASHA TV',
  );
  late final TextEditingController
  _settingsUpdateMessage = TextEditingController(
    text:
        'Toleo jipya linahitajika ili kuendelea kutumia app. Pakua kutoka Play Store kisha fungua tena.',
  );
  AdminPageId _page = AdminPageId.dashboard;
  String? _slideQuery = '';
  String? _slideFilter = 'all';

  /// Desktop: whether sidebar is open (main gets left margin). Starts open on wide screens.
  bool _sidebarOpen = false;
  bool _sidebarInitialized = false;
  final List<_Toast> _toasts = [];
  Timer? _adminRefreshTimer;
  Timer? _statsRefreshTimer;
  static const _pricingPlanKeys = ['weekly', 'gold', 'platinum'];
  _PricingControllersBundle? _pricingCtrls;

  _PricingControllersBundle get _pricingFields {
    _pricingCtrls ??= _PricingControllersBundle();
    return _pricingCtrls!;
  }

  bool get _isMobile => MediaQuery.sizeOf(context).width < 1024;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _users = generateUsers(_rand);
    _channels = generateChannels(_rand);

    /// Empty until bootstrap/admin APIs load — avoids fake carousel rows overwriting real DB state in the UI.
    _slides = [];
    _pricing = defaultPricingPlans();
    _ensurePricingControllers();
    _subscriptions = generateSubscriptions(_rand, _users, _pricing);
    _payments = generatePayments(_rand, _users);
    _notifications = staticNotifications();
    _logs = generateLogs(_rand);
    unawaited(_bootstrapAdminData());
    // Stats only matter on dashboard — polling every page rebuilds Users/Channels and causes ANRs.
    // Takwimu refreshes every 10s (live view), the dashboard every 20s.
    _statsRefreshTimer = Timer.periodic(const Duration(seconds: 10), (t) {
      if (!mounted || !_hasAdminSession || _appLifecyclePaused) return;
      if (_page == AdminPageId.analytics ||
          (_page == AdminPageId.dashboard && t.tick.isEven)) {
        unawaited(_refreshDashboardStats());
      }
    });
    // Full sync is expensive; keep it rare and page-aware.
    _adminRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted || !_hasAdminSession || _appLifecyclePaused) return;
      if (_page == AdminPageId.pricing) return;
      // Never interrupt an active user search with a full dashboard sync.
      if (_normalizedUserSearchQuery().isNotEmpty) return;
      if (_page == AdminPageId.users) {
        unawaited(_searchUsersFromBackend(silent: true));
        return;
      }
      if (_page == AdminPageId.dashboard || _page == AdminPageId.analytics) {
        unawaited(_refreshDashboardStats());
        return;
      }
      if (_page == AdminPageId.notifications) {
        unawaited(_loadReminderData());
        unawaited(_reloadNotifications());
        return;
      }
      if (_page == AdminPageId.payments) {
        unawaited(_reloadPayments());
        return;
      }
      unawaited(_hydrateFromBackend());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecyclePaused =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden;
  }

  /// Load settings (API key), then server bootstrap. Local pricing prefs apply **only** if bootstrap fails (offline).
  Future<void> _bootstrapAdminData() async {
    await _loadSavedSettings();
    if (!mounted) return;
    final hydrated = await _hydrateFromBackend();
    if (!mounted) return;
    if (_hasAdminSession) await _refreshDashboardStats();
    if (!mounted) return;
    if (!hydrated) await _loadSavedPricing();
    if (mounted && _hasAdminSession) unawaited(_loadReminderData());
  }

  Future<void> _loadSavedSettings() async {
    final sp = await SharedPreferences.getInstance();
    final wa = sp.getString(AdminPrefsKeys.supportWhatsapp);
    if (!mounted) return;
    setState(() {
      if (wa != null && wa.isNotEmpty) {
        _settings.whatsappNumber = wa;
        _settingsWhatsapp.text = wa;
      }
    });
  }

  Future<void> _adminLogout() async {
    await widget.auth.logout();
    if (!mounted) return;
    _showToast('Umetoka.', _ToastType.info);
  }

  Future<void> _handleAdminUnauthorized() async {
    if (!mounted) return;
    // The password screen shows "Login imeisha" because the logout is marked as expired.
    await widget.auth.logout(expired: true);
  }

  /// Remaining time of the 24-hour login, e.g. "saa 5 zimebaki".
  String _sessionRemainingLabel() {
    final left = widget.auth.remaining;
    if (left == null) return 'Hujaingia';
    if (left.inMinutes < 1) return 'Login Expired';
    if (left.inHours >= 1) return 'Login: saa ${left.inHours} zimebaki';
    return 'login: dakika ${left.inMinutes} zimebaki';
  }

  String _formatRelative(DateTime? dt) {
    if (dt == null) return 'sasa hivi';
    final sec = DateTime.now().difference(dt).inSeconds;
    if (sec < 5) return 'sasa hivi';
    if (sec < 60) return 'sekunde $sec zilizopita';
    if (sec < 3600) return 'dakika ${sec ~/ 60} zilizopita';
    return 'saa ${sec ~/ 3600} zilizopita';
  }

  String _dashboardSubtitle() {
    if (!_hasAdminSession) return 'Ingia ili kuona data za moja kwa moja';
    if (_statsRefreshFailed && _dashboardStats == null) {
      return 'Imeshindwa kupakia takwimu · vuta chini ujaribu tena';
    }
    if (_statsRefreshFailed) {
      return 'Kusasisha kumeshindikana · mwisho ${_formatRelative(_statsFetchedAt)}';
    }
    if (_dashboardStats != null) {
      return 'Data za moja kwa moja · zilisasishwa ${_formatRelative(_statsFetchedAt)}';
    }
    return 'Inapakia takwimu…';
  }

  /// English month / weekday abbreviations (from the server or `to_char`) → Swahili.
  static const _swahiliLabels = {
    'Jan': 'Jan',
    'Feb': 'Feb',
    'Mar': 'Mac',
    'Apr': 'Apr',
    'May': 'Mei',
    'Jun': 'Jun',
    'Jul': 'Jul',
    'Aug': 'Ago',
    'Sep': 'Sep',
    'Oct': 'Okt',
    'Nov': 'Nov',
    'Dec': 'Des',
    'Mon': 'Jtt',
    'Tue': 'Jnn',
    'Wed': 'Jtn',
    'Thu': 'Alh',
    'Fri': 'Iju',
    'Sat': 'Jmo',
    'Sun': 'Jpi',
  };

  String _swLabel(String raw) => _swahiliLabels[raw.trim()] ?? raw;

  /// Status words stored in English in the database → Swahili for display.
  String _swStatus(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'active':
        return 'hai';
      case 'suspended':
        return 'imezuiwa';
      case 'inactive':
        return 'haifanyi kazi';
      case 'completed':
        return 'imekamilika';
      case 'pending':
        return 'inasubiri';
      case 'failed':
        return 'imeshindwa';
      case 'cancelled':
      case 'canceled':
        return 'imeghairiwa';
      case 'expired':
        return 'imeisha';
      case 'premium':
        return 'premium';
      case 'free':
        return 'bure';
      default:
        return raw;
    }
  }

  /// Admin log action codes → Swahili.
  String _swLogAction(String raw) {
    switch (raw.trim()) {
      case 'grant_premium':
        return 'Ametoa premium';
      case 'revoke_premium':
        return 'Ameondoa premium';
      case 'bulk_revoke_premium':
        return 'Ameondoa premium (wengi)';
      case 'send_reminders':
        return 'Ametuma reminder';
      case 'send_reminders_failed':
        return 'Kutuma reminder kumeshindikana';
      case 'verify_payment':
        return 'Amehakiki malipo (SonicPesa)';
      case 'verify_pending_payments':
        return 'Amehakiki malipo yanayosubiri';
      default:
        return raw.replaceAll('_', ' ');
    }
  }

  /// Lightweight stats poll — keeps dashboard metrics fresh without a full admin sync.
  Future<bool> _refreshDashboardStats({bool notify = true}) async {
    if (!_hasAdminSession) return false;
    try {
      final res = await http
          .get(
            Uri.parse('$_apiBase/api/v1/admin/stats/overview'),
            headers: _adminHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 401 || res.statusCode == 403) {
        await _handleAdminUnauthorized();
        return false;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        if (notify && mounted) setState(() => _statsRefreshFailed = true);
        return false;
      }
      final map = await _decodeJsonMapSafe(res.body);
      if (map == null) {
        if (notify && mounted) setState(() => _statsRefreshFailed = true);
        return false;
      }
      final stats = _parseStatsJson(
        (map['stats'] as Map?)?.cast<String, dynamic>(),
      );
      if (stats == null) {
        if (notify && mounted) setState(() => _statsRefreshFailed = true);
        return false;
      }
      if (!mounted) return false;
      final onStatsPage =
          _page == AdminPageId.dashboard || _page == AdminPageId.analytics;
      if (notify) {
        // Only the stats pages show live numbers; elsewhere skip the rebuild.
        if (!onStatsPage && !_statsRefreshFailed) {
          _dashboardStats = stats;
          _statsFetchedAt = DateTime.now();
        } else {
          setState(() {
            _dashboardStats = stats;
            _statsFetchedAt = DateTime.now();
            _statsRefreshFailed = false;
          });
        }
      } else {
        _dashboardStats = stats;
        _statsFetchedAt = DateTime.now();
        _statsRefreshFailed = false;
      }
      return true;
    } catch (_) {
      if (notify && mounted) setState(() => _statsRefreshFailed = true);
      return false;
    }
  }

  Future<Map<String, dynamic>?> _decodeJsonMapSafe(String body) async {
    try {
      if (body.length < 12000) {
        return jsonDecode(body) as Map<String, dynamic>;
      }
      // Large sync payloads — keep decode off the UI isolate to avoid ANR.
      return await compute(_decodeJsonMapIsolate, body);
    } catch (_) {
      try {
        return jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _loadSavedPricing() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('washatvPricing');
    if (raw == null || !mounted) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        for (final e in map.entries) {
          if (_pricing.containsKey(e.key)) {
            _pricing[e.key] = _pricingFromJson(
              e.value as Map<String, dynamic>,
              _pricing[e.key]!,
            );
          }
        }
      });
      if (mounted) _syncPricingControllersFromPlans();
    } catch (_) {}
  }

  Map<String, String> _adminHeaders() => {
    ...widget.auth.headers(contentType: 'application/json'),
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
  };

  /// DELETE without JSON Content-Type — fewer CORS preflight issues on Flutter web.
  Map<String, String> _adminHeadersForDelete() => widget.auth.headers();

  List<AdminSlide> _parseAdminSlidesJson(List<dynamic> raw) {
    return raw
        .whereType<Map>()
        .map((rawItem) {
          final j = rawItem.cast<String, dynamic>();
          return AdminSlide(
            id: _s(j['id']),
            title: _s(j['title']),
            subtitle: _s(j['subtitle']),
            imageUrl: _s(j['image_url']),
            premium: j['premium'] as bool? ?? false,
            active: j['active'] as bool? ?? true,
            sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
          );
        })
        .where((s) => s.id.isNotEmpty)
        .toList();
  }

  Uri _adminSlideUri(String slideId) => Uri.parse(
    '$_apiBase/api/v1/admin/slides/${Uri.encodeComponent(slideId)}',
  );

  Uri _adminChannelUri(String channelId) => Uri.parse(
    '$_apiBase/api/v1/admin/channels/${Uri.encodeComponent(channelId)}',
  );

  List<AdminChannel> _parseAdminChannelsJson(List<dynamic> raw) {
    return raw
        .whereType<Map>()
        .map((rawItem) {
          final j = rawItem.cast<String, dynamic>();
          final category = _s(j['category']);
          return AdminChannel(
            id: _s(j['id']),
            name: _s(j['name']),
            category: category.isEmpty ? kAppChannelCategories.first : category,
            premium: j['premium'] as bool? ?? false,
            live: j['live'] as bool? ?? false,
            status: _s(j['status'], fallback: 'active'),
            thumbnail: _s(j['thumbnail']),
            streamUrl: _s(j['stream_url'] ?? j['streamUrl']),
            viewers: (j['viewers'] as num?)?.toInt() ?? 0,
            rating: _s(j['rating'], fallback: '5.0'),
            drm: _s(j['drm'], fallback: 'none'),
            drmClearKey: _s(j['drm_clear_key'] ?? j['drmClearKey']),
          );
        })
        .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
        .toList();
  }

  Future<bool> _refreshChannelsFromServer() async {
    if (!_hasAdminSession) return false;
    try {
      final res = await http
          .get(
            Uri.parse('$_apiBase/api/v1/admin/channels'),
            headers: _adminHeadersForDelete(),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = (map['channels'] as List?)?.cast<dynamic>() ?? const [];
      if (!mounted) return false;
      setState(() => _channels = _parseAdminChannelsJson(raw));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _refreshSlidesFromServer() async {
    if (!_hasAdminSession) return false;
    try {
      final res = await http
          .get(
            Uri.parse('$_apiBase/api/v1/admin/slides'),
            headers: _adminHeadersForDelete(),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final raw = (map['slides'] as List?)?.cast<dynamic>() ?? const [];
      if (!mounted) return false;
      setState(() => _slides = _parseAdminSlidesJson(raw));
      return true;
    } catch (_) {
      return false;
    }
  }

  String _adminHttpError(http.Response res) {
    final body = res.body.trim();
    if (body.isNotEmpty && body.length < 120) return body;
    return 'HTTP ${res.statusCode}';
  }

  /// Same rule as [PublicApiService._publicGetHeaders]: on web, extra headers can force CORS preflight on GET.
  Map<String, String> get _publicBootstrapHeaders => kIsWeb
      ? <String, String>{}
      : const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'};

  String _normalizedUserSearchQuery() {
    // Collapse whitespace; keep dashes (Device IDs use them). Uppercase helps WTV-… matches.
    return _userSearch.text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<bool> _hydrateFromBackend({bool forceUsersReload = false}) async {
    final existing = _hydrateInFlight;
    if (existing != null && !forceUsersReload) return existing;

    final seq = ++_hydrateSeq;
    final future = _hydrateFromBackendImpl(seq);
    _hydrateInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_hydrateInFlight, future)) _hydrateInFlight = null;
    }
  }

  Future<bool> _hydrateFromBackendImpl(int seq) async {
    try {
      final searchQ = _normalizedUserSearchQuery();
      final browsingUsers =
          searchQ.isEmpty &&
          _usersFilter == 0 &&
          _usersLimit == _usersBrowseLimit;
      final bootstrapUri = Uri.parse(
        '$_apiBase/api/v1/public/bootstrap',
      ).replace(queryParameters: const {'since': '0'});
      final bootstrapFuture = http
          .get(bootstrapUri, headers: _publicBootstrapHeaders)
          .timeout(const Duration(seconds: 15));
      // While searching, keep sync payload small (no user dump) — users come from /admin/users.
      final adminFuture = _hasAdminSession
          ? http
                .get(
                  Uri.parse('$_apiBase/api/v1/admin/sync').replace(
                    queryParameters: {
                      'limit': browsingUsers ? '$_usersBrowseLimit' : '1',
                      if (!browsingUsers) 'skip_users': '1',
                    },
                  ),
                  headers: _adminHeaders(),
                )
                .timeout(const Duration(seconds: 30))
          : null;

      late final http.Response bootstrapRes;
      http.Response? adminRes;
      if (adminFuture != null) {
        final pair = await Future.wait<http.Response>([
          bootstrapFuture,
          adminFuture,
        ]);
        bootstrapRes = pair[0];
        adminRes = pair[1];
      } else {
        bootstrapRes = await bootstrapFuture;
      }

      if (seq != _hydrateSeq || !mounted) return false;

      final bootstrapOk =
          bootstrapRes.statusCode >= 200 && bootstrapRes.statusCode < 300;
      Map<String, dynamic>? bootstrapMap;
      if (bootstrapOk) {
        bootstrapMap = await _decodeJsonMapSafe(bootstrapRes.body);
      }

      Map<String, dynamic>? adminSyncMap;
      if (adminRes != null) {
        if (adminRes.statusCode == 401 || adminRes.statusCode == 403) {
          await _handleAdminUnauthorized();
          return false;
        }
        if (adminRes.statusCode >= 200 && adminRes.statusCode < 300) {
          adminSyncMap = await _decodeJsonMapSafe(adminRes.body);
        } else if (_hasAdminSession) {
          adminSyncMap = await _fetchLegacyAdminBundle();
        }
      }

      if (seq != _hydrateSeq || !mounted) return false;
      setState(() {
        if (bootstrapMap != null) {
          final map = bootstrapMap;
          final rawPlans = (map['plans'] as List?)?.cast<dynamic>() ?? const [];
          final rawChannels =
              (map['channels'] as List?)?.cast<dynamic>() ?? const [];
          final rawSlidesFromBootstrap =
              (map['slides'] as List?)?.cast<dynamic>() ?? const [];
          final settings =
              (map['settings'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          for (final p in rawPlans) {
            if (p is! Map) continue;
            final j = p.cast<String, dynamic>();
            final key = _s(j['plan_key']);
            final existing = _pricing[key];
            if (existing == null) continue;
            final priceRaw = j['price'];
            final price = priceRaw is num
                ? priceRaw.toDouble()
                : double.tryParse(priceRaw?.toString().trim() ?? '');
            final daysRaw = j['duration_days'];
            final days = daysRaw is num
                ? daysRaw.toInt()
                : int.tryParse(daysRaw?.toString().trim() ?? '');
            final en = j['enabled'];
            final bool? enabled = en is bool
                ? en
                : en is num
                ? en != 0
                : en is String
                ? (en.toLowerCase() == 'true' || en == '1')
                : null;
            final name = (j['name'] as String?)?.trim();
            if (name != null && name.isNotEmpty) existing.name = name;
            if (price != null) existing.price = price;
            existing.originalPrice = existing.price;
            existing.discount = 0;
            if (days != null) existing.duration = days;
            if (enabled != null) existing.enabled = enabled;
          }
          if (adminSyncMap == null) {
            _channels = _parseAdminChannelsJson(rawChannels);
            _slides = rawSlidesFromBootstrap
                .whereType<Map>()
                .map((rawItem) {
                  final j = rawItem.cast<String, dynamic>();
                  return AdminSlide(
                    id: _s(j['id']),
                    title: _s(j['title']),
                    subtitle: _s(j['subtitle']),
                    imageUrl: _s(j['image_url']),
                    premium: j['premium'] as bool? ?? false,
                    active: j['active'] as bool? ?? true,
                    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
                  );
                })
                .where(
                  (s) =>
                      s.id.isNotEmpty &&
                      s.title.isNotEmpty &&
                      s.imageUrl.isNotEmpty,
                )
                .toList();
          }
          final wa = _s(settings['whatsapp_number']);
          _settings.whatsappNumber = wa;
          _settingsWhatsapp.text = wa;
          final site = _s(settings['site_name']);
          if (site.isNotEmpty) {
            _settings.siteName = site;
            _settingsSiteName.text = site;
          }
          final subEn = settings['subscription_enabled'];
          if (subEn is bool) {
            _settings.subscriptionEnabled = subEn;
          } else if (subEn is num) {
            _settings.subscriptionEnabled = subEn != 0;
          }
          final maint = settings['maintenance_mode'];
          if (maint is bool) {
            _settings.maintenanceMode = maint;
          } else if (maint is num) {
            _settings.maintenanceMode = maint != 0;
          }
          _applyForceUpdateSettingsFromMap(settings);
        }
        if (adminSyncMap != null) {
          // Preserve in-progress search results: only replace users when browsing.
          _applyAdminSyncPayload(adminSyncMap, applyUsers: browsingUsers);
        }
      });
      if (mounted) {
        _syncPricingControllersFromPlans();
        await _persistPricingMapToPrefs();
      }
      if (_hasAdminSession && _dashboardStats == null) {
        await _refreshDashboardStats(notify: false);
        if (mounted) setState(() {});
      }
      // Re-apply active search after a browse sync so the list stays accurate.
      if (_hasAdminSession && !browsingUsers && mounted && seq == _hydrateSeq) {
        unawaited(_searchUsersFromBackend());
      }
      return bootstrapOk || adminSyncMap != null || _dashboardStats != null;
    } catch (_) {
      return false;
    }
  }

  /// Lightweight users-only fetch — used for search so we never rebuild the whole dashboard.
  Future<void> _searchUsersFromBackend({bool silent = false}) async {
    if (!_hasAdminSession) return;
    final q = _normalizedUserSearchQuery();
    final filter = _userFilterKeys[_usersFilter];
    final limit = _usersLimit;
    if (!mounted) return;
    if (!silent) setState(() => _usersSearchLoading = true);
    bool stale() =>
        _normalizedUserSearchQuery() != q ||
        _userFilterKeys[_usersFilter] != filter ||
        _usersLimit != limit;
    try {
      final res = await http
          .get(
            Uri.parse('$_apiBase/api/v1/admin/users').replace(
              queryParameters: {
                'limit': '$limit',
                if (q.isNotEmpty) 'q': q,
                if (filter != 'all') 'filter': filter,
                if (filter == 'premium') 'premium': '1',
              },
            ),
            headers: _adminHeaders(),
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (res.statusCode == 401 || res.statusCode == 403) {
        await _handleAdminUnauthorized();
        return;
      }
      if (stale()) return;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        setState(() => _usersSearchLoading = false);
        return;
      }
      final map = await _decodeJsonMapSafe(res.body);
      if (map == null || stale()) {
        if (mounted) setState(() => _usersSearchLoading = false);
        return;
      }
      final rawUsers = map['users'];
      final totalRaw = map['total'] ?? map['users_total'];
      final matchedRaw = map['matched'] ?? map['premium_total'];
      final countsRaw = map['counts'];
      final serverFilter = _s(map['filter']);
      setState(() {
        if (rawUsers is List) {
          _users = _parseUsersJson(rawUsers);
          _sortAdminLists();
          _usersLoadedFilter = serverFilter.isNotEmpty
              ? serverFilter
              : (filter == 'premium' && map['premium_only'] == true
                    ? 'premium'
                    : 'all');
        }
        if (totalRaw is num) {
          _usersTotal = totalRaw.toInt();
        } else if (totalRaw is String) {
          _usersTotal = int.tryParse(totalRaw) ?? _users.length;
        }
        _usersMatched = matchedRaw == null ? _users.length : _toInt(matchedRaw);
        _userCounts = countsRaw is Map
            ? {for (final k in _userFilterKeys) k: _toInt(countsRaw[k])}
            : null;
        _usersSearchLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _usersSearchLoading = false);
    }
  }

  String _pricingPriceText(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

  void _ensurePricingControllers() {
    final fields = _pricingFields;
    for (final key in _pricingPlanKeys) {
      final p = _pricing[key];
      if (p == null) continue;
      fields.name.putIfAbsent(key, () => TextEditingController(text: p.name));
      fields.price.putIfAbsent(
        key,
        () => TextEditingController(text: _pricingPriceText(p.price)),
      );
      fields.days.putIfAbsent(
        key,
        () => TextEditingController(text: '${p.duration}'),
      );
    }
  }

  void _syncPricingControllersFromPlans() {
    _ensurePricingControllers();
    final fields = _pricingFields;
    for (final key in _pricingPlanKeys) {
      final p = _pricing[key];
      if (p == null) continue;
      fields.name[key]!.text = p.name;
      fields.price[key]!.text = _pricingPriceText(p.price);
      fields.days[key]!.text = '${p.duration}';
    }
  }

  void _applyPricingControllersToPlans() {
    final fields = _pricingFields;
    for (final key in _pricingPlanKeys) {
      final p = _pricing[key];
      if (p == null) continue;
      final name = fields.name[key]?.text.trim() ?? '';
      if (name.isNotEmpty) p.name = name;
      final priceRaw =
          fields.price[key]?.text.replaceAll(RegExp(r'[^0-9.]'), '').trim() ??
          '';
      final price = double.tryParse(priceRaw);
      if (price != null && price >= 0) {
        p.price = price;
        p.originalPrice = price;
      }
      final days = int.tryParse(fields.days[key]?.text.trim() ?? '');
      if (days != null && days > 0) p.duration = days;
    }
    _syncPricingDerivedFields();
  }

  void _applyPricingRowToPlan(String key, Map<String, dynamic> j) {
    final p = _pricing[key];
    if (p == null) return;
    final name = (j['name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) p.name = name;
    final priceRaw = j['price'];
    final price = priceRaw is num
        ? priceRaw.toDouble()
        : double.tryParse(priceRaw?.toString().trim() ?? '');
    if (price != null) {
      p.price = price;
      p.originalPrice = price;
    }
    final daysRaw = j['duration_days'];
    final days = daysRaw is num
        ? daysRaw.toInt()
        : int.tryParse(daysRaw?.toString().trim() ?? '');
    if (days != null && days > 0) p.duration = days;
    final en = j['enabled'];
    if (en is bool) {
      p.enabled = en;
    } else if (en is num) {
      p.enabled = en != 0;
    }
    p.discount = 0;
  }

  Future<void> _persistPricingMapToPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final map = {
        for (final e in _pricing.entries) e.key: _pricingToJson(e.value),
      };
      await sp.setString('washatvPricing', jsonEncode(map));
    } catch (_) {}
  }

  String _s(Object? value, {String fallback = ''}) =>
      value?.toString().trim() ?? fallback;
  DateTime? _dt(Object? value) {
    final s = value?.toString();
    if (s == null || s.isEmpty) return null;
    final parsed = DateTime.tryParse(s);
    return parsed?.toLocal();
  }

  List<double> _numList(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) {
      if (e is num) return e.toDouble();
      if (e is String) return double.tryParse(e) ?? 0;
      return 0.0;
    }).toList();
  }

  int _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  double _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  void _sortAdminLists() {
    _users.sort((a, b) {
      final c = b.createdAt.compareTo(a.createdAt);
      if (c != 0) return c;
      return b.id.compareTo(a.id);
    });
    _payments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _logs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _subscriptions.sort((a, b) => b.endDate.compareTo(a.endDate));
  }

  List<AdminUser> _parseUsersJson(List<dynamic> raw) {
    return raw.whereType<Map>().map((rawItem) {
      final j = rawItem.cast<String, dynamic>();
      final deviceRaw = _s(j['device_id']);
      return AdminUser(
        id: _s(j['id']),
        name: _s(j['name'], fallback: 'Viewer'),
        phone: _s(j['phone'], fallback: 'N/A'),
        deviceId: deviceRaw.isEmpty ? null : deviceRaw,
        status: _s(j['status'], fallback: 'active'),
        subscription: _s(j['subscription'], fallback: 'free'),
        createdAt:
            _dt(j['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        premiumUntil: _dt(j['premium_until']),
        adminAccessUntil: _dt(j['admin_access_until']),
      );
    }).toList();
  }

  AdminDashboardStats? _parseStatsJson(Map<String, dynamic>? s) {
    if (s == null) return null;
    final totals = (s['totals'] as Map?)?.cast<String, dynamic>() ?? const {};
    final growth =
        (s['user_growth'] as Map?)?.cast<String, dynamic>() ?? const {};
    final revenue =
        (s['revenue_overview'] as Map?)?.cast<String, dynamic>() ?? const {};
    final daily =
        (s['daily_registrations'] as Map?)?.cast<String, dynamic>() ?? const {};
    final mix = (s['plan_mix'] as Map?)?.cast<String, dynamic>() ?? const {};
    final live = (s['live'] as Map?)?.cast<String, dynamic>() ?? const {};
    final d14 = (s['daily_14'] as Map?)?.cast<String, dynamic>() ?? const {};
    final d14Labels = ((d14['labels'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
    final d14Regs = _numList(d14['registrations']);
    final d14Buys = _numList(d14['purchases']);
    final d14Rev = _numList(d14['revenue']);
    final days14 = <AdminDayStat>[
      for (var i = 0; i < d14Labels.length; i++)
        if (DateTime.tryParse(d14Labels[i]) case final day?)
          AdminDayStat(
            day: day,
            registrations: i < d14Regs.length ? d14Regs[i].round() : 0,
            purchases: i < d14Buys.length ? d14Buys[i].round() : 0,
            revenue: i < d14Rev.length ? d14Rev[i] : 0,
          ),
    ];
    final recent = ((s['recent_payments'] as List?) ?? const [])
        .whereType<Map>()
        .map((raw) {
          final j = raw.cast<String, dynamic>();
          final order = _s(j['order_id']);
          final plan = _s(j['plan_key']);
          return AdminRecentPayment(
            id: _s(j['id']),
            orderId: order.isEmpty ? null : order,
            userName: _s(j['user_name'], fallback: 'Viewer'),
            amount: _toDouble(j['amount']),
            planKey: plan.isEmpty ? null : plan,
            status: _s(j['status'], fallback: 'pending'),
            at: _dt(j['at']) ?? DateTime.now(),
          );
        })
        .toList();
    return AdminDashboardStats(
      live: AdminLiveStats(
        onlineNow: _toInt(live['online_now']),
        activeToday: _toInt(live['active_today']),
        active7d: _toInt(live['active_7d']),
        newUsersToday: _toInt(live['new_users_today']),
        pendingPayments: _toInt(live['pending_payments']),
        failedToday: _toInt(live['failed_today']),
        revenue7d: _toDouble(live['revenue_7d']),
        revenue30d: _toDouble(live['revenue_30d']),
      ),
      days14: days14,
      recentPayments: recent,
      totalUsers: _toInt(totals['users']),
      premiumUsers: _toInt(totals['premium_users']),
      freeUsers: _toInt(totals['free_users']),
      activeChannels: _toInt(totals['active_channels']),
      revenue: _toDouble(totals['revenue']),
      monthLabels: ((growth['labels'] as List?) ?? const [])
          .map((e) => _swLabel(e.toString()))
          .toList(),
      newUsersPerMonth: _numList(growth['new_users']),
      premiumPurchasesPerMonth: _numList(growth['premium_purchases']),
      revenuePerMonth: _numList(revenue['amounts']),
      dailyLabels: ((daily['labels'] as List?) ?? const [])
          .map((e) => _swLabel(e.toString()))
          .toList(),
      dailyRegistrations: _numList(daily['counts']),
      planWeekly: _toInt(mix['weekly']),
      planGold: _toInt(mix['gold']),
      planPlatinum: _toInt(mix['platinum']),
      planOther: _toInt(mix['other']),
    );
  }

  Future<Map<String, dynamic>?> _fetchLegacyAdminBundle() async {
    try {
      final results = await Future.wait([
        http
            .get(
              Uri.parse('$_apiBase/api/v1/admin/users').replace(
                queryParameters: {
                  'limit': '$_usersBrowseLimit',
                  if (_normalizedUserSearchQuery().isNotEmpty)
                    'q': _normalizedUserSearchQuery(),
                },
              ),
              headers: _adminHeaders(),
            )
            .timeout(const Duration(seconds: 20)),
        http
            .get(
              Uri.parse('$_apiBase/api/v1/admin/channels'),
              headers: _adminHeaders(),
            )
            .timeout(const Duration(seconds: 15)),
        http
            .get(
              Uri.parse('$_apiBase/api/v1/admin/slides'),
              headers: _adminHeaders(),
            )
            .timeout(const Duration(seconds: 15)),
        http
            .get(
              Uri.parse('$_apiBase/api/v1/admin/transactions'),
              headers: _adminHeaders(),
            )
            .timeout(const Duration(seconds: 15)),
        http
            .get(
              Uri.parse('$_apiBase/api/v1/admin/notifications'),
              headers: _adminHeaders(),
            )
            .timeout(const Duration(seconds: 15)),
        http
            .get(
              Uri.parse('$_apiBase/api/v1/admin/stats/overview'),
              headers: _adminHeaders(),
            )
            .timeout(const Duration(seconds: 15)),
        http
            .get(
              Uri.parse('$_apiBase/api/v1/admin/subscriptions'),
              headers: _adminHeaders(),
            )
            .timeout(const Duration(seconds: 15)),
        http
            .get(
              Uri.parse('$_apiBase/api/v1/admin/logs'),
              headers: _adminHeaders(),
            )
            .timeout(const Duration(seconds: 15)),
      ]);
      for (final res in results) {
        if (res.statusCode == 401 || res.statusCode == 403) {
          await _handleAdminUnauthorized();
          return null;
        }
      }
      final bundle = <String, dynamic>{};
      if (results[0].statusCode >= 200 && results[0].statusCode < 300) {
        final usersMap = jsonDecode(results[0].body) as Map;
        bundle['users'] = usersMap['users'];
        bundle['users_total'] = usersMap['total'];
      }
      if (results[1].statusCode >= 200 && results[1].statusCode < 300) {
        bundle['channels'] = (jsonDecode(results[1].body) as Map)['channels'];
      }
      if (results[2].statusCode >= 200 && results[2].statusCode < 300) {
        bundle['slides'] = (jsonDecode(results[2].body) as Map)['slides'];
      }
      if (results[3].statusCode >= 200 && results[3].statusCode < 300) {
        bundle['transactions'] =
            (jsonDecode(results[3].body) as Map)['transactions'];
      }
      if (results[4].statusCode >= 200 && results[4].statusCode < 300) {
        bundle['notifications'] =
            (jsonDecode(results[4].body) as Map)['notifications'];
      }
      if (results[5].statusCode >= 200 && results[5].statusCode < 300) {
        bundle['stats'] = (jsonDecode(results[5].body) as Map)['stats'];
      }
      if (results[6].statusCode >= 200 && results[6].statusCode < 300) {
        bundle['subscriptions'] =
            (jsonDecode(results[6].body) as Map)['subscriptions'];
      }
      if (results[7].statusCode >= 200 && results[7].statusCode < 300) {
        bundle['logs'] = (jsonDecode(results[7].body) as Map)['logs'];
      }
      return bundle.isEmpty ? null : bundle;
    } catch (_) {
      return null;
    }
  }

  void _applyAdminSyncPayload(
    Map<String, dynamic> adminMap, {
    bool applyUsers = true,
  }) {
    if (applyUsers) {
      final rawUsers = adminMap['users'];
      if (rawUsers is List) _users = _parseUsersJson(rawUsers);
      final totalRaw = adminMap['users_total'] ?? adminMap['total'];
      if (totalRaw is num) {
        _usersTotal = totalRaw.toInt();
      } else if (totalRaw is String) {
        _usersTotal = int.tryParse(totalRaw) ?? _users.length;
      } else if (rawUsers is List) {
        _usersTotal = _users.length;
      }
      _usersMatched = _usersTotal;
      if (rawUsers is List) _usersLoadedFilter = 'all';
    } else {
      // Still refresh authoritative total when present so header stays honest.
      final totalRaw = adminMap['users_total'] ?? adminMap['total'];
      if (totalRaw is num) {
        _usersTotal = totalRaw.toInt();
      } else if (totalRaw is String) {
        final parsed = int.tryParse(totalRaw);
        if (parsed != null) _usersTotal = parsed;
      }
    }

    final rawChannels = adminMap['channels'];
    if (rawChannels is List) _channels = _parseAdminChannelsJson(rawChannels);

    final rawSlides = adminMap['slides'];
    if (rawSlides is List) _slides = _parseAdminSlidesJson(rawSlides);

    final rawTx = adminMap['transactions'];
    if (rawTx is List) _payments = _parsePaymentsJson(rawTx);

    final rawNoti = adminMap['notifications'];
    if (rawNoti is List) _notifications = _parseNotificationsJson(rawNoti);

    final stats = _parseStatsJson(
      (adminMap['stats'] as Map?)?.cast<String, dynamic>(),
    );
    if (stats != null) {
      _dashboardStats = stats;
      _statsFetchedAt = DateTime.now();
      _statsRefreshFailed = false;
    }

    final rawSubs = adminMap['subscriptions'];
    if (rawSubs is List) {
      _subscriptions = rawSubs.whereType<Map>().map((rawItem) {
        final j = rawItem.cast<String, dynamic>();
        return AdminSubscription(
          id: _s(j['id']),
          userName: _s(j['user_name'], fallback: 'Viewer'),
          plan: _s(j['plan'], fallback: 'gold'),
          price: (j['price'] as num?)?.toDouble() ?? 0,
          endDate: _dt(j['end_date']) ?? DateTime.now(),
          status: _s(j['status'], fallback: 'active'),
        );
      }).toList();
    }

    final rawLogs = adminMap['logs'];
    if (rawLogs is List) {
      _logs = rawLogs.whereType<Map>().map((rawItem) {
        final j = rawItem.cast<String, dynamic>();
        return AdminLog(
          id: _s(j['id']),
          adminName: _s(j['admin_name'], fallback: 'Admin'),
          action: _s(j['action']),
          details: _s(j['details']),
          createdAt: _dt(j['created_at']) ?? DateTime.now(),
        );
      }).toList();
    }

    _sortAdminLists();
  }

  AdminPayment _parsePaymentJson(Map<String, dynamic> j) {
    final meta = j['metadata'] is Map
        ? (j['metadata'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final remote = _s(meta['sonicpesa_status']);
    return AdminPayment(
      id: _s(j['id']),
      userName: _s(j['user_name'], fallback: 'Viewer'),
      amount:
          (j['amount'] as num?)?.toDouble() ??
          double.tryParse(_s(j['amount'])) ??
          0,
      method: _s(j['method'], fallback: 'N/A'),
      status: _s(j['status'], fallback: 'completed'),
      transactionId: _s(j['provider_ref'], fallback: _s(j['id'])),
      createdAt:
          _dt(j['completed_at']) ?? _dt(j['created_at']) ?? DateTime.now(),
      planKey: _s(j['plan_key']).isEmpty ? null : _s(j['plan_key']),
      phone: _s(j['phone']),
      provider: _s(j['provider']),
      verifiedAt: _dt(meta['verified_at']),
      remoteStatus: remote.isEmpty ? null : remote,
    );
  }

  List<AdminPayment> _parsePaymentsJson(List<dynamic> raw) => raw
      .whereType<Map>()
      .map((m) => _parsePaymentJson(m.cast<String, dynamic>()))
      .toList();

  Future<void> _reloadPayments() async {
    if (!_hasAdminSession) return;
    try {
      final res = await http
          .get(
            Uri.parse('$_apiBase/api/v1/admin/transactions'),
            headers: _adminHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 401 || res.statusCode == 403) {
        await _handleAdminUnauthorized();
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final map = await _decodeJsonMapSafe(res.body);
      final raw = map?['transactions'];
      if (raw is! List || !mounted) return;
      setState(() => _payments = _parsePaymentsJson(raw));
    } catch (_) {}
  }

  Future<void> _onPullRefresh() async {
    if (_page == AdminPageId.users) {
      await Future.wait([_searchUsersFromBackend(), _refreshDashboardStats()]);
      return;
    }
    await Future.wait([_hydrateFromBackend(), _refreshDashboardStats()]);
  }

  /// Last 7 calendar months ending this month (labels + bucket starts).
  ({List<String> labels, List<DateTime> starts}) _lastSevenMonths() {
    final now = DateTime.now();
    final month0 = DateTime(now.year, now.month);
    final labels = <String>[];
    final starts = <DateTime>[];
    const months = [
      'Jan',
      'Feb',
      'Mac',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    for (var i = 6; i >= 0; i--) {
      final start = DateTime(month0.year, month0.month - i);
      starts.add(start);
      labels.add(months[start.month - 1]);
    }
    return (labels: labels, starts: starts);
  }

  bool _inMonth(DateTime dt, DateTime monthStart) {
    final next = DateTime(monthStart.year, monthStart.month + 1);
    return !dt.isBefore(monthStart) && dt.isBefore(next);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Calendar day in Tanzania (EAT, UTC+3) — matches backend Africa/Dar_es_Salaam cutoff at 00:00.
  bool _isTodayTanzania(DateTime dt) {
    final tzNow = DateTime.now().toUtc().add(const Duration(hours: 3));
    final tzDt = dt.toUtc().add(const Duration(hours: 3));
    return tzNow.year == tzDt.year &&
        tzNow.month == tzDt.month &&
        tzNow.day == tzDt.day;
  }

  /// Today's completed collections only (Tanzania day). Never use lifetime API totals for this card.
  double _todayRevenueTzs() {
    return _payments
        .where((p) => p.status == 'completed' && _isTodayTanzania(p.createdAt))
        .fold<double>(0, (a, p) => a + p.amount);
  }

  AdminDashboardStats? _statsFromLocalLists() {
    if (_users.isEmpty && _payments.isEmpty && _channels.isEmpty) return null;
    final buckets = _lastSevenMonths();
    final newUsers = buckets.starts
        .map(
          (m) =>
              _users.where((u) => _inMonth(u.createdAt, m)).length.toDouble(),
        )
        .toList();
    final premiumBuys = buckets.starts
        .map(
          (m) => _payments
              .where((p) => p.status == 'completed' && _inMonth(p.createdAt, m))
              .length
              .toDouble(),
        )
        .toList();
    final revenue = buckets.starts
        .map(
          (m) => _payments
              .where((p) => p.status == 'completed' && _inMonth(p.createdAt, m))
              .fold<double>(0, (a, p) => a + p.amount),
        )
        .toList();
    final today = DateTime.now();
    final dayStarts = List.generate(
      7,
      (i) => DateTime(today.year, today.month, today.day - (6 - i)),
    );
    const dayLabels = ['Jtt', 'Jnn', 'Jtn', 'Alh', 'Iju', 'Jmo', 'Jpi'];
    final daily = dayStarts
        .map(
          (d) =>
              _users.where((u) => _sameDay(u.createdAt, d)).length.toDouble(),
        )
        .toList();
    final dailyLabels = dayStarts.map((d) => dayLabels[d.weekday - 1]).toList();
    final premium = _users.where((u) => u.effectivePremium).length;
    final total = _users.length;
    var week = 0, gold = 0, plat = 0, other = 0;
    for (final p in _payments.where((x) => x.status == 'completed')) {
      switch (p.planKey) {
        case 'weekly':
          week++;
        case 'gold':
          gold++;
        case 'platinum':
          plat++;
        default:
          other++;
      }
    }
    return AdminDashboardStats(
      totalUsers: total,
      premiumUsers: premium,
      freeUsers: (total - premium).clamp(0, total),
      activeChannels: _channels.where((c) => c.status == 'active').length,
      revenue: _todayRevenueTzs(),
      monthLabels: buckets.labels,
      newUsersPerMonth: newUsers,
      premiumPurchasesPerMonth: premiumBuys,
      revenuePerMonth: revenue,
      dailyLabels: dailyLabels,
      dailyRegistrations: daily,
      planWeekly: week,
      planGold: gold,
      planPlatinum: plat,
      planOther: other,
    );
  }

  AdminDashboardStats? get _effectiveStats {
    if (_dashboardStats != null) return _dashboardStats;
    if (!_hasAdminSession) return _statsFromLocalLists();
    return null;
  }

  PricingPlan _pricingFromJson(Map<String, dynamic> j, PricingPlan fallback) {
    return PricingPlan(
      name: j['name'] as String? ?? fallback.name,
      originalPrice:
          (j['originalPrice'] as num?)?.toDouble() ?? fallback.originalPrice,
      price: (j['price'] as num?)?.toDouble() ?? fallback.price,
      discount: (j['discount'] as num?)?.toInt() ?? fallback.discount,
      duration: (j['duration'] as num?)?.toInt() ?? fallback.duration,
      features:
          (j['features'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          fallback.features,
      popular: j['popular'] as bool? ?? fallback.popular,
      enabled: j['enabled'] as bool? ?? fallback.enabled,
      colorKey: j['color'] as String? ?? fallback.colorKey,
    );
  }

  Map<String, dynamic> _pricingToJson(PricingPlan p) => {
    'name': p.name,
    'originalPrice': p.originalPrice,
    'price': p.price,
    'discount': p.discount,
    'duration': p.duration,
    'features': p.features,
    'popular': p.popular,
    'enabled': p.enabled,
    'color': p.colorKey,
  };

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _adminRefreshTimer?.cancel();
    _statsRefreshTimer?.cancel();
    _settingsSiteName.dispose();
    _settingsWhatsapp.dispose();
    _settingsMinBuild.dispose();
    _settingsMinVersion.dispose();
    _settingsLatestVersion.dispose();
    _settingsLatestBuild.dispose();
    _settingsPlayStoreUrl.dispose();
    _settingsUpdateTitle.dispose();
    _settingsUpdateMessage.dispose();
    _pricingCtrls?.dispose();
    _pricingCtrls = null;
    _globalSearch.dispose();
    _userSearchDebounce?.cancel();
    _userSearch.dispose();
    _subsSearch.dispose();
    _paySearch.dispose();
    super.dispose();
  }

  void _navigate(AdminPageId p) {
    setState(() {
      _page = p;
      if (_isMobile) _sidebarOpen = false;
    });
    if (p == AdminPageId.notifications && _hasAdminSession) {
      unawaited(_loadReminderData());
    }
    if (p == AdminPageId.users && _hasAdminSession) {
      unawaited(_searchUsersFromBackend(silent: _users.isNotEmpty));
    }
  }

  /// Header "Search..." finds users by Device ID / name / phone / USR id.
  void _onGlobalSearchSubmitted(String raw) {
    final q = raw.trim();
    if (q.isEmpty) return;
    _userSearch.text = q;
    _globalSearch.clear();
    setState(() {
      _page = AdminPageId.users;
      _usersFilter = 0;
      _usersLimit = _usersBrowseLimit;
      if (_isMobile) _sidebarOpen = false;
    });
    if (_hasAdminSession) unawaited(_searchUsersFromBackend());
  }

  void _toggleSidebar() => setState(() => _sidebarOpen = !_sidebarOpen);

  void _showToast(String msg, _ToastType t) {
    final toast = _Toast(msg, t);
    setState(() => _toasts.add(toast));
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _toasts.remove(toast));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sidebarInitialized) {
      _sidebarInitialized = true;
      _sidebarOpen = !_isMobile;
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final mobile = w < 1024;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_sidebarOpen) setState(() => _sidebarOpen = false);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                const Positioned.fill(child: AdminAmbientBackground()),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!mobile)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.ease,
                        width: _sidebarOpen ? 260 : 0,
                        child: _sidebarOpen
                            ? ClipRect(child: _buildSidebar(mobile))
                            : const SizedBox.shrink(),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          _buildHeader(mobile, w),
                          Expanded(
                            child: RefreshIndicator(
                              color: const Color(0xFF818CF8),
                              backgroundColor: AdminColors.bgSecondary,
                              onRefresh: _onPullRefresh,
                              // Users + Channels own their scroll views (virtualized). Nested
                              // shrinkWrap grids/lists of many tiles caused Android ANRs.
                              // New key per page → the entrance animation replays on every navigation.
                              child: KeyedSubtree(
                                key: ValueKey(_page),
                                child: FadeSlideIn(
                                  offset: 18,
                                  child: _page == AdminPageId.channels
                                      ? Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            16,
                                            16,
                                            16,
                                            mobile ? 100 : 16,
                                          ),
                                          child: _pageChannels(),
                                        )
                                      : (_page == AdminPageId.users ||
                                            _page ==
                                                AdminPageId.subscriptions ||
                                            _page == AdminPageId.payments)
                                      ? _ownScrollPage(mobile, switch (_page) {
                                          AdminPageId.users => _userSlivers(),
                                          AdminPageId.subscriptions =>
                                            _subscriptionSlivers(),
                                          _ => _paymentSlivers(),
                                        })
                                      : SingleChildScrollView(
                                          physics:
                                              const AlwaysScrollableScrollPhysics(
                                                parent: BouncingScrollPhysics(),
                                              ),
                                          padding: EdgeInsets.fromLTRB(
                                            16,
                                            16,
                                            16,
                                            mobile ? 100 : 24,
                                          ),
                                          child: _buildPage(),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (mobile && _sidebarOpen) ...[
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _sidebarOpen = false),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                        child: Container(color: const Color(0x99000000)),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: 280,
                    child: Material(
                      color: AdminColors.bgSecondary,
                      elevation: 8,
                      child: _buildSidebar(true),
                    ),
                  ),
                ],
                Positioned(top: 12, right: 12, child: _toastStack()),
              ],
            ),
          ),
          extendBody: mobile,
          bottomNavigationBar: mobile ? _bottomNav() : null,
        ),
      ),
    );
  }

  Widget _toastStack() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: _toasts.map((t) {
        final bg = switch (t.type) {
          _ToastType.success => const Color(0xFF10B981),
          _ToastType.error => const Color(0xFFEF4444),
          _ToastType.warning => const Color(0xFFF59E0B),
          _ToastType.info => const Color(0xFF6366F1),
        };
        final icon = switch (t.type) {
          _ToastType.success => Icons.check_circle_rounded,
          _ToastType.error => Icons.error_rounded,
          _ToastType.warning => Icons.warning_amber_rounded,
          _ToastType.info => Icons.info_rounded,
        };
        return TweenAnimationBuilder<double>(
          key: ObjectKey(t),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          builder: (context, v, child) => Opacity(
            opacity: v.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset((1 - v) * 40, 0),
              child: child,
            ),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            constraints: BoxConstraints(
              maxWidth: min(380.0, MediaQuery.sizeOf(context).width - 24),
            ),
            padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
            decoration: BoxDecoration(
              color: AdminColors.bgSecondary,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: bg.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(color: bg.withValues(alpha: 0.25), blurRadius: 24),
                const BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: bg.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: bg, size: 17),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    t.message,
                    style: const TextStyle(
                      color: AdminColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  static const _navItems = <AdminPageId, (IconData, String)>{
    AdminPageId.dashboard: (Icons.space_dashboard_rounded, 'Dashibodi'),
    AdminPageId.analytics: (Icons.insights_rounded, 'Takwimu'),
    AdminPageId.users: (Icons.groups_rounded, 'Watumiaji'),
    AdminPageId.subscriptions: (Icons.workspace_premium_rounded, 'Usajili'),
    AdminPageId.payments: (Icons.account_balance_wallet_rounded, 'Malipo'),
    AdminPageId.pricing: (Icons.sell_rounded, 'Bei za vifurushi'),
    AdminPageId.channels: (Icons.live_tv_rounded, 'Chaneli'),
    AdminPageId.slides: (Icons.view_carousel_rounded, 'Mabango'),
    AdminPageId.notifications: (
      Icons.notifications_active_rounded,
      'Arifa na Reminder',
    ),
    AdminPageId.settings: (Icons.tune_rounded, 'Mipangilio'),
    AdminPageId.logs: (Icons.history_rounded, 'Kumbukumbu za shughuli'),
  };

  Widget _headerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return Tooltip(
      message: tooltip,
      child: AdminPressable(
        onTap: onTap,
        lift: 0,
        pressedScale: 0.9,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0x0DFFFFFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: Icon(icon, size: 20, color: const Color(0xFFCBD5E1)),
            ),
            if (badge > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  decoration: BoxDecoration(
                    color: AdminColors.accentDanger,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AdminColors.bgPrimary, width: 2),
                  ),
                  child: Text(
                    badge > 99 ? '99+' : '$badge',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool mobile, double width) {
    final showTitle = width >= 640;
    final page = _navItems[_page]!;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xF70A0E17), Color(0xE60A0E17)],
        ),
        border: Border(bottom: BorderSide(color: AdminColors.borderSubtle)),
      ),
      child: Row(
        children: [
          _HamburgerButton(open: _sidebarOpen, onTap: _toggleSidebar),
          const SizedBox(width: 14),
          if (showTitle)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Column(
                key: ValueKey(_page),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.$2,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${adminGreeting()} · ${adminSwahiliDate()}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: EdgeInsets.only(left: showTitle ? 20 : 0, right: 12),
                  child: TextField(
                    controller: _globalSearch,
                    style: const TextStyle(fontSize: 13),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _onGlobalSearchSubmitted,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Tafuta mtumiaji (Device ID / jina / simu)…',
                      hintStyle: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 12.5,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 19,
                        color: Color(0xFF818CF8),
                      ),
                      filled: true,
                      fillColor: const Color(0x99111827),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0x14FFFFFF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Color(0xFF6366F1),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _headerIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Arifa na Reminder',
            onTap: () => _navigate(AdminPageId.notifications),
            badge: _reminderSummary?.expiringUnsent ?? 0,
          ),
          if (!mobile) ...[
            const SizedBox(width: 10),
            Tooltip(
              message: _sessionRemainingLabel(),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
                  ),
                  boxShadow: [
                    BoxShadow(color: Color(0x40F97316), blurRadius: 14),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text(
                  'SA',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSidebar(bool mobileCloseBtn) {
    return Container(
      decoration: const BoxDecoration(
        color: AdminColors.bgSecondary,
        border: Border(right: BorderSide(color: AdminColors.borderSubtle)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF9333EA)],
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x596366F1),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (r) => const LinearGradient(
                          colors: [Color(0xFF818CF8), Color(0xFFA78BFA)],
                        ).createShader(r),
                        child: const Text(
                          'Waisa',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            letterSpacing: -0.3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const Text(
                        'Paneli ya Usimamizi',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                if (mobileCloseBtn)
                  IconButton(
                    onPressed: () => setState(() => _sidebarOpen = false),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                const AdminNavSection('Muhtasari'),
                _navRow(AdminPageId.dashboard),
                _navRow(AdminPageId.analytics),
                const AdminNavSection('Wateja na mapato'),
                _navRow(AdminPageId.users),
                _navRow(AdminPageId.subscriptions),
                _navRow(AdminPageId.payments),
                _navRow(AdminPageId.pricing),
                const AdminNavSection('Maudhui'),
                _navRow(AdminPageId.channels),
                _navRow(AdminPageId.slides),
                const AdminNavSection('Mawasiliano'),
                _navRow(
                  AdminPageId.notifications,
                  badge: _reminderSummary?.expiringUnsent ?? 0,
                ),
                const AdminNavSection('Mfumo'),
                _navRow(AdminPageId.settings),
                _navRow(AdminPageId.logs),
              ],
            ),
          ),
          _sidebarSessionCard(),
        ],
      ),
    );
  }

  /// Who is signed in, and how much of the 24-hour login is left (progress bar).
  Widget _sidebarSessionCard() {
    final left = widget.auth.remaining ?? Duration.zero;
    final fraction = (left.inSeconds / const Duration(hours: 24).inSeconds)
        .clamp(0.0, 1.0);
    final barColor = fraction > 0.25
        ? AdminColors.accentSuccess
        : AdminColors.accentWarning;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(12),
      decoration: adminCardDecoration(radius: 16, shadow: false),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
                  ),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'SA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Msimamizi',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _sessionRemainingLabel(),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Toka',
                onPressed: _adminLogout,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0x14EF4444),
                ),
                icon: const Icon(
                  Icons.logout_rounded,
                  size: 17,
                  color: Color(0xFFF87171),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: const Color(0x14FFFFFF),
                color: barColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navRow(AdminPageId id, {int badge = 0}) {
    final (icon, label) = _navItems[id]!;
    final active = _page == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: const Color(0x0AFFFFFF),
          onTap: () => _navigate(id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: active
                  ? const LinearGradient(
                      colors: [Color(0x336366F1), Color(0x0A6366F1)],
                    )
                  : null,
              border: Border.all(
                color: active ? const Color(0x336366F1) : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    gradient: active
                        ? const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF9333EA)],
                          )
                        : null,
                    color: active ? null : const Color(0x0AFFFFFF),
                    boxShadow: active
                        ? const [
                            BoxShadow(
                              color: Color(0x4D6366F1),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: active ? Colors.white : const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? Colors.white : AdminColors.textPrimary,
                    ),
                  ),
                ),
                if (badge > 0) ...[
                  const _PulseDot(),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x33EF4444),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFF87171),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Floating bottom bar for phones; the active tab grows a pill behind its icon.
  Widget _bottomNav() {
    const items = <(AdminPageId, String)>[
      (AdminPageId.dashboard, 'Dashibodi'),
      (AdminPageId.users, 'Watumiaji'),
      (AdminPageId.channels, 'Chaneli'),
      (AdminPageId.notifications, 'Arifa'),
      (AdminPageId.payments, 'Malipo'),
      (AdminPageId.settings, 'Mipangilio'),
    ];
    final unsent = _reminderSummary?.expiringUnsent ?? 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: const Color(0xF2111827),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0x1AFFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: items.map((e) {
            final active = _page == e.$1;
            final color = active ? Colors.white : const Color(0xFF6B7280);
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _navigate(e.$1),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                            horizontal: active ? 14 : 6,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: active
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF6366F1),
                                      Color(0xFF9333EA),
                                    ],
                                  )
                                : null,
                            boxShadow: active
                                ? const [
                                    BoxShadow(
                                      color: Color(0x596366F1),
                                      blurRadius: 14,
                                      offset: Offset(0, 4),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            _navItems[e.$1]!.$1,
                            size: 19,
                            color: color,
                          ),
                        ),
                        if (e.$1 == AdminPageId.notifications && unsent > 0)
                          const Positioned(
                            right: 2,
                            top: 0,
                            child: _PulseDot(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                        color: active
                            ? const Color(0xFFC7D2FE)
                            : const Color(0xFF6B7280),
                      ),
                      child: Text(
                        e.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPage() {
    switch (_page) {
      case AdminPageId.dashboard:
        return _pageDashboard();
      case AdminPageId.channels:
        return _pageChannels();
      case AdminPageId.slides:
        return _pageSlides();
      case AdminPageId.users:
      case AdminPageId.subscriptions:
      case AdminPageId.payments:
        // Virtualized pages with their own scroll view, see _ownScrollPage.
        return const SizedBox.shrink();
      case AdminPageId.pricing:
        return _pagePricing();
      case AdminPageId.notifications:
        return _pageNotifications();
      case AdminPageId.analytics:
        return _pageAnalytics();
      case AdminPageId.settings:
        return _pageSettings();
      case AdminPageId.logs:
        return _pageLogs();
    }
  }

  // --- Dashboard ---
  Widget _pageDashboard() {
    final stats = _effectiveStats;
    final loadingStats = _hasAdminSession && stats == null;
    final totalUsers =
        stats?.totalUsers ?? (loadingStats ? null : _users.length);
    final premiumUsers =
        stats?.premiumUsers ??
        (loadingStats ? null : _users.where((u) => u.effectivePremium).length);
    final freeUsers =
        stats?.freeUsers ??
        (loadingStats
            ? null
            : ((totalUsers ?? 0) - (premiumUsers ?? 0)).clamp(
                0,
                totalUsers ?? 0,
              ));
    final activeChannels =
        stats?.activeChannels ??
        (loadingStats
            ? null
            : _channels.where((c) => c.status == 'active').length);
    // Always derive from local payments for Tanzania "today" — production API may still
    // return lifetime totals until the backend redeploys.
    final revenue = loadingStats && _payments.isEmpty
        ? null
        : _todayRevenueTzs();
    final recentUsers = _users.take(5).toList();
    final recentPayments = _payments
        .where((p) => p.status == 'completed')
        .take(5)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeSlideIn(
          child: _dashboardHero(
            premiumUsers: premiumUsers,
            totalUsers: totalUsers,
          ),
        ),
        const SizedBox(height: 18),
        _dashboardReminderCallout(),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final cols = w < 640 ? 2 : (w < 1100 ? 3 : 5);
            final cards = [
              _statCard(
                label: 'Watumiaji wote',
                value: loadingStats ? null : totalUsers ?? 0,
                icon: Icons.groups_rounded,
                iconBg: const Color(0x336366F1),
                iconColor: const Color(0xFF818CF8),
                onTap: () => _navigate(AdminPageId.users),
              ),
              _statCard(
                label: 'Premium',
                value: loadingStats ? null : premiumUsers ?? 0,
                icon: Icons.workspace_premium_rounded,
                iconBg: const Color(0x33F59E0B),
                iconColor: const Color(0xFFFBBF24),
                onTap: () => _navigate(AdminPageId.subscriptions),
              ),
              _statCard(
                label: 'Bure',
                value: loadingStats ? null : freeUsers ?? 0,
                icon: Icons.person_outline_rounded,
                iconBg: const Color(0x3394A3B8),
                iconColor: const Color(0xFFCBD5E1),
                onTap: () => _navigate(AdminPageId.users),
              ),
              _statCard(
                label: 'Chaneli hai',
                value: loadingStats ? null : activeChannels ?? 0,
                icon: Icons.live_tv_rounded,
                iconBg: const Color(0x3310B981),
                iconColor: const Color(0xFF34D399),
                onTap: () => _navigate(AdminPageId.channels),
              ),
              _statCard(
                label: 'Mapato ya leo',
                value: loadingStats ? null : revenue ?? 0,
                format: fmtTzs,
                icon: Icons.payments_rounded,
                iconBg: const Color(0x33A855F7),
                iconColor: const Color(0xFFC084FC),
                onTap: () => _navigate(AdminPageId.payments),
              ),
            ];
            return GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent: 136,
              ),
              children: [
                for (var i = 0; i < cards.length; i++)
                  FadeSlideIn(index: i + 1, child: cards[i]),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 1024;
            final charts = [
              _chartCard('Ukuaji wa watumiaji', 300, _userGrowthChart()),
              _chartCard('Muhtasari wa mapato (TSh)', 300, _revenueBarChart()),
            ];
            if (stacked) {
              return Column(
                children: [charts[0], const SizedBox(height: 16), charts[1]],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: charts[0]),
                const SizedBox(width: 16),
                Expanded(child: charts[1]),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 1024;
            final blocks = [
              _recentTableCard(
                title: 'Watumiaji wa karibuni',
                onViewAll: () => _navigate(AdminPageId.users),
                columnFlex: const [5, 2, 2, 2],
                columns: const ['Mtumiaji', 'Hali', 'Kifurushi', 'Tarehe'],
                rows: recentUsers
                    .map(
                      (u) => [
                        _userCell(u.name),
                        _compactPill(
                          _swStatus(u.status),
                          u.status == 'active'
                              ? AdminColors.accentSuccess
                              : AdminColors.accentDanger,
                        ),
                        _compactPill(
                          u.effectivePremium ? 'premium' : 'bure',
                          u.effectivePremium
                              ? AdminColors.accentWarning
                              : const Color(0xFF6B7280),
                        ),
                        _recentCellText(
                          _fmtDate(u.createdAt),
                          color: AdminColors.textSecondary,
                        ),
                      ],
                    )
                    .toList(),
              ),
              _recentTableCard(
                title: 'Malipo ya karibuni',
                onViewAll: () => _navigate(AdminPageId.payments),
                columnFlex: const [4, 2, 2, 2],
                columns: const ['Mtumiaji', 'Kiasi', 'Hali', 'Tarehe'],
                rows: recentPayments
                    .map(
                      (p) => [
                        _recentCellText(p.userName, weight: FontWeight.w500),
                        _recentCellText(
                          fmtTzs(p.amount),
                          weight: FontWeight.w800,
                        ),
                        _paymentStatusPill(p.status),
                        _recentCellText(
                          _fmtDate(p.createdAt),
                          color: AdminColors.textSecondary,
                        ),
                      ],
                    )
                    .toList(),
              ),
            ];
            if (stacked) {
              return Column(
                children: [blocks[0], const SizedBox(height: 16), blocks[1]],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: blocks[0]),
                const SizedBox(width: 16),
                Expanded(child: blocks[1]),
              ],
            );
          },
        ),
      ],
    );
  }

  /// "N vinaisha ndani ya siku 3 · M vimeisha" → opens the reminders page.
  Widget _dashboardReminderCallout() {
    final s = _reminderSummary;
    if (s == null || (s.expiring == 0 && s.expired == 0)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: const Color(0x1FF59E0B),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _navigate(AdminPageId.notifications),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x55F59E0B)),
            ),
            child: Row(
              children: [
                const Icon(Icons.alarm_rounded, color: Color(0xFFFBBF24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vifurushi ${s.expiring} vinaisha ndani ya siku ${s.days} · ${s.expired} vimeisha',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        s.expiringUnsent > 0
                            ? '${s.expiringUnsent} bado hawajapata reminder — bonyeza kutuma'
                            : 'Bonyeza kuona watumiaji na kutuma reminder',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AdminColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFFBBF24),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Greeting card with the day's headline numbers and one-tap shortcuts to the common jobs.
  Widget _dashboardHero({
    required int? premiumUsers,
    required int? totalUsers,
  }) {
    final premiumShare = (totalUsers ?? 0) > 0
        ? (premiumUsers ?? 0) / totalUsers!
        : 0.0;
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.add_rounded, 'Ongeza chaneli', () => _showChannelEditor()),
      (Icons.campaign_rounded, 'Tuma arifa', () => _modalSendNotification()),
      (
        Icons.alarm_rounded,
        'Tuma reminder',
        () => _navigate(AdminPageId.notifications),
      ),
      (
        Icons.receipt_long_rounded,
        'Malipo',
        () => _navigate(AdminPageId.payments),
      ),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: adminBrandGradient,
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D6366F1),
            blurRadius: 32,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative rings — purely visual.
          Positioned(
            right: -60,
            top: -70,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x1FFFFFFF), width: 28),
              ),
            ),
          ),
          Positioned(
            right: 90,
            bottom: -90,
            child: Container(
              width: 170,
              height: 170,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x0FFFFFFF),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x26FFFFFF),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF34D399),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _dashboardStats != null
                                ? 'Moja kwa moja'
                                : 'Inapakia…',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${adminGreeting()}, Msimamizi',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${adminSwahiliDate()} · ${_dashboardSubtitle()}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xD9FFFFFF),
                  ),
                ),
                if ((totalUsers ?? 0) > 0) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Premium ${(premiumShare * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: premiumShare),
                            duration: const Duration(milliseconds: 1100),
                            curve: Curves.easeOutCubic,
                            builder: (context, v, _) => LinearProgressIndicator(
                              value: v,
                              minHeight: 6,
                              backgroundColor: const Color(0x33FFFFFF),
                              color: const Color(0xFFFBBF24),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in actions)
                      AdminPressable(
                        onTap: a.$3,
                        lift: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x26FFFFFF),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0x33FFFFFF)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(a.$1, size: 16, color: Colors.white),
                              const SizedBox(width: 6),
                              Text(
                                a.$2,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [value] null = still loading (shimmer bar). Numbers count up and glide on refresh.
  Widget _statCard({
    required String label,
    required num? value,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    String Function(num v)? format,
    VoidCallback? onTap,
  }) {
    final fmt = format ?? (num v) => v.round().toString();
    return AdminPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: adminCardDecoration(glow: iconColor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: iconColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(icon, color: iconColor, size: 19),
                ),
                const Spacer(),
                if (onTap != null)
                  Icon(
                    Icons.arrow_outward_rounded,
                    size: 15,
                    color: iconColor.withValues(alpha: 0.7),
                  ),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: value == null
                    ? Container(
                        width: 70,
                        height: 22,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0x14FFFFFF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      )
                    : AnimatedCount(
                        value: value,
                        format: fmt,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AdminColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartCard(String title, double height, Widget chart) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  gradient: adminBrandGradient,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(height: height, child: chart),
        ],
      ),
    );
  }

  Widget _userGrowthChart() {
    final stats = _effectiveStats;
    final labels = stats?.monthLabels.isNotEmpty == true
        ? stats!.monthLabels
        : const ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul'];
    final newUsers =
        stats?.newUsersPerMonth ?? List<double>.filled(labels.length, 0);
    final premiumBuys =
        stats?.premiumPurchasesPerMonth ??
        List<double>.filled(labels.length, 0);
    final n = labels.length;
    final maxY = [
      ...newUsers,
      ...premiumBuys,
    ].fold<double>(0, (a, b) => b > a ? b : a);
    final yMax = maxY <= 0 ? 1.0 : maxY * 1.15;
    final totalSpots = List.generate(
      n,
      (i) => FlSpot(i.toDouble(), i < newUsers.length ? newUsers[i] : 0),
    );
    final premiumSpots = List.generate(
      n,
      (i) => FlSpot(i.toDouble(), i < premiumBuys.length ? premiumBuys[i] : 0),
    );
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yMax / 4,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: const Color(0x08FFFFFF), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 28,
              getTitlesWidget: (v, m) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  labels[v.toInt().clamp(0, n > 0 ? n - 1 : 0)],
                  style: const TextStyle(
                    color: AdminColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, m) => Text(
                v >= 1000
                    ? '${(v / 1000).toStringAsFixed(1)}k'
                    : v.toInt().toString(),
                style: const TextStyle(
                  color: AdminColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: totalSpots,
            isCurved: true,
            color: AdminColors.accentPrimary,
            barWidth: 2,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0x146366F1),
            ),
          ),
          LineChartBarData(
            spots: premiumSpots,
            isCurved: true,
            color: AdminColors.accentWarning,
            barWidth: 2,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: const Color(0x14F59E0B),
            ),
          ),
        ],
        minX: 0,
        maxX: n > 1 ? (n - 1).toDouble() : 1,
        minY: 0,
        maxY: yMax,
      ),
    );
  }

  Widget _revenueBarChart() {
    final stats = _effectiveStats;
    final labels = stats?.monthLabels.isNotEmpty == true
        ? stats!.monthLabels
        : const ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul'];
    final vals =
        stats?.revenuePerMonth ?? List<double>.filled(labels.length, 0);
    final n = labels.length;
    final maxVal = vals.fold<double>(0, (a, b) => b > a ? b : a);
    final maxY = maxVal <= 0 ? 1.0 : maxVal * 1.15;
    return BarChart(
      BarChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: const Color(0x08FFFFFF), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        maxY: maxY,
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, m) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  labels[v.toInt().clamp(0, n > 0 ? n - 1 : 0)],
                  style: const TextStyle(
                    color: AdminColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (v, m) => Text(
                fmtTzsAxis(v),
                style: const TextStyle(
                  color: AdminColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ),
        barGroups: List.generate(
          n,
          (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: i < vals.length ? vals[i] : 0,
                color: const Color(0xB36366F1),
                width: 18,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentTableCard({
    required String title,
    required VoidCallback onViewAll,
    required List<String> columns,
    required List<int> columnFlex,
    required List<List<Widget>> rows,
  }) {
    assert(
      columns.length == columnFlex.length,
      'columnFlex must match columns',
    );
    for (final r in rows) {
      assert(r.length == columns.length, 'row length must match columns');
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Ona zote',
                  style: TextStyle(fontSize: 10, color: Color(0xFF818CF8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _recentTableHeaderRow(columns, columnFlex),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          const SizedBox(height: 4),
          ...rows.map(
            (cells) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _recentDataRow(cells, columnFlex),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentTableHeaderRow(List<String> columns, List<int> columnFlex) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(columns.length, (i) {
        return Expanded(
          flex: columnFlex[i],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Text(
              columns[i].toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AdminColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _recentDataRow(List<Widget> cells, List<int> columnFlex) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(cells.length, (i) {
        return Expanded(
          flex: columnFlex[i],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: cells[i],
          ),
        );
      }),
    );
  }

  Widget _recentCellText(String s, {FontWeight? weight, Color? color}) {
    return Text(
      s,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        fontWeight: weight,
        color: color ?? AdminColors.textPrimary,
      ),
    );
  }

  /// Scales down in very narrow cells so status text (e.g. "completed") is never clipped.
  Widget _compactPill(String text, Color color) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: color,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _paymentStatusPill(String status) {
    final c = status == 'completed'
        ? AdminColors.accentSuccess
        : status == 'failed'
        ? AdminColors.accentDanger
        : AdminColors.accentWarning;
    return _compactPill(_swStatus(status), c);
  }

  Widget _userCell(String name) {
    final ini = name.length >= 2
        ? name.substring(0, 2).toUpperCase()
        : name.toUpperCase();
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF9333EA)],
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            ini,
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      MaterialLocalizations.of(context).formatCompactDate(d);

  String _formatLogDateTime(DateTime d) {
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${t(d.month)}-${t(d.day)} ${t(d.hour)}:${t(d.minute)}';
  }

  // --- Users ---
  void _onUserSearchChanged(String _) {
    setState(() => _usersLimit = _usersBrowseLimit);
    _userSearchDebounce?.cancel();
    _userSearchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || !_hasAdminSession) return;
      unawaited(_searchUsersFromBackend());
    });
  }

  static const _expiredColor = Color(0xFFFB923C);
  static const _freeColor = Color(0xFF818CF8);

  bool _userMatchesFilter(AdminUser u, String key) {
    switch (key) {
      case 'premium':
        return u.effectivePremium;
      case 'expired':
        return !u.effectivePremium &&
            (u.premiumUntil != null || u.adminAccessUntil != null);
      case 'free':
        return !u.effectivePremium &&
            u.premiumUntil == null &&
            u.adminAccessUntil == null;
      case 'blocked':
        return u.status == 'suspended';
      default:
        return true;
    }
  }

  Map<String, int> _localUserCounts() => {
    for (final k in _userFilterKeys)
      k: k == 'all'
          ? (_usersTotal > 0 ? _usersTotal : _users.length)
          : _users.where((u) => _userMatchesFilter(u, k)).length,
  };

  /// Latest premium end, paid or admin-granted.
  DateTime? _userAccessEnd(AdminUser u) {
    final a = u.premiumUntil;
    final b = u.adminAccessUntil;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  ({String label, Color color, IconData icon}) _userStatusMeta(AdminUser u) {
    if (u.status == 'suspended') {
      return (
        label: 'Imezuiwa',
        color: AdminColors.accentDanger,
        icon: Icons.block_rounded,
      );
    }
    final end = _userAccessEnd(u);
    if (u.effectivePremium && end != null) {
      final left = end.difference(DateTime.now());
      final span = left.inDays >= 1
          ? 'siku ${left.inDays}'
          : left.inHours >= 1
          ? 'saa ${left.inHours}'
          : 'dak ${max(1, left.inMinutes)}';
      return (
        label: 'Premium · $span',
        color: AdminColors.accentWarning,
        icon: Icons.workspace_premium_rounded,
      );
    }
    if (end != null) {
      return (
        label: 'Imeisha · ${_fmtDate(end.toLocal())}',
        color: _expiredColor,
        icon: Icons.history_rounded,
      );
    }
    return (label: 'Bure', color: _freeColor, icon: Icons.person_rounded);
  }

  List<Color>? _userAvatarColors(AdminUser u) {
    if (u.status == 'suspended') {
      return const [Color(0xFFEF4444), Color(0xFF991B1B)];
    }
    if (u.effectivePremium) {
      return const [Color(0xFFF59E0B), Color(0xFFD97706)];
    }
    if (_userAccessEnd(u) != null) {
      return const [Color(0xFF64748B), Color(0xFF334155)];
    }
    return null;
  }

  void _setUsersFilter(int i) {
    if (i == _usersFilter) return;
    setState(() {
      _usersFilter = i;
      _usersLimit = _usersBrowseLimit;
    });
    unawaited(_searchUsersFromBackend());
  }

  void _loadMoreUsers() {
    setState(() => _usersLimit = min(5000, _usersLimit + _usersBrowseLimit));
    unawaited(_searchUsersFromBackend());
  }

  List<Widget> _userSlivers() {
    final q = _normalizedUserSearchQuery();
    final ql = q.toLowerCase();
    final filterKey = _userFilterKeys[_usersFilter];
    final list = _users.where((u) {
      if (_usersLoadedFilter != filterKey &&
          !_userMatchesFilter(u, filterKey)) {
        return false;
      }
      // Rows already come from the server search; this only keeps typing responsive.
      if (ql.isEmpty || !_usersSearchLoading) return true;
      return '${u.name} ${u.phone} ${u.deviceId ?? ''} ${u.id}'
          .toLowerCase()
          .contains(ql);
    }).toList();
    final counts = _userCounts ?? _localUserCounts();
    int count(String k) => counts[k] ?? 0;
    final total = _usersTotal > 0 ? _usersTotal : _users.length;
    final matched = _userCounts != null
        ? count(filterKey)
        : (_usersLoadedFilter == filterKey && _usersMatched > list.length
              ? _usersMatched
              : list.length);
    final canLoadMore =
        _usersLoadedFilter == filterKey &&
        !_usersSearchLoading &&
        matched > list.length &&
        _users.length >= _usersLimit &&
        _usersLimit < 5000;

    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pageTitleRow(
              title: 'Watumiaji',
              subtitle:
                  '$total jumla · ${count('premium')} premium · ${count('blocked')} wamezuiwa',
              action: _usersMenu(),
            ),
            const SizedBox(height: 14),
            AdminSearchField(
              controller: _userSearch,
              hint: 'Tafuta jina, simu, Device ID (WTV-…) au USR-…',
              onChanged: _onUserSearchChanged,
              loading: _usersSearchLoading,
            ),
            const SizedBox(height: 12),
            AdminFilterChips(
              options: [
                AdminFilterOption('Wote', count: count('all')),
                AdminFilterOption(
                  'Premium',
                  count: count('premium'),
                  color: AdminColors.accentWarning,
                ),
                AdminFilterOption(
                  'Zimeisha',
                  count: count('expired'),
                  color: _expiredColor,
                ),
                AdminFilterOption(
                  'Bure',
                  count: count('free'),
                  color: _freeColor,
                ),
                AdminFilterOption(
                  'Wamezuiwa',
                  count: count('blocked'),
                  color: AdminColors.accentDanger,
                ),
              ],
              selected: _usersFilter,
              onSelected: _setUsersFilter,
            ),
            const SizedBox(height: 12),
            Text(
              list.isEmpty
                  ? ''
                  : 'Inaonyesha ${list.length} kati ya $matched · gusa mtumiaji kuona maelezo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                color: AdminColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
      if (list.isEmpty)
        SliverToBoxAdapter(
          child: _emptyListState(
            q.isEmpty ? Icons.groups_outlined : Icons.search_off_rounded,
            _usersSearchLoading
                ? 'Inapakia watumiaji…'
                : q.isNotEmpty
                ? 'Hakuna matokeo ya "$q".\nTumia Device ID kamili (WTV-XXXX-XXXXXXXX) au USR-….'
                : 'Hakuna watumiaji katika kundi hili.',
          ),
        )
      else
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 640,
            mainAxisExtent: 68,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _userTile(list[i]),
            childCount: list.length,
          ),
        ),
      if (canLoadMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Center(
              child: _btnOutline(
                label: 'Onyesha zaidi (${matched - list.length} wamebaki)',
                icon: Icons.expand_more_rounded,
                onTap: _loadMoreUsers,
              ),
            ),
          ),
        ),
    ];
  }

  Widget _usersMenu() {
    PopupMenuItem<String> item(String value, IconData icon, String label) =>
        PopupMenuItem(
          value: value,
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF818CF8)),
              const SizedBox(width: 10),
              Text(label, style: const TextStyle(fontSize: 13)),
            ],
          ),
        );
    return PopupMenuButton<String>(
      tooltip: 'Zaidi',
      color: AdminColors.bgSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      icon: const Icon(
        Icons.more_vert_rounded,
        color: AdminColors.textSecondary,
      ),
      onSelected: (v) {
        switch (v) {
          case 'refresh':
            unawaited(_searchUsersFromBackend());
          case 'notify':
            _modalSendNotification();
          case 'revoke':
            unawaited(_showBulkRevokePremiumDialog());
        }
      },
      itemBuilder: (_) => [
        item('refresh', Icons.refresh_rounded, 'Onyesha upya'),
        item('notify', Icons.campaign_outlined, 'Tuma arifa kwa wote'),
        item('revoke', Icons.remove_circle_outline, 'Ondoa premium kwa wengi'),
      ],
    );
  }

  Widget _userStatusPill(({String label, Color color, IconData icon}) meta) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 11, color: meta.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              meta.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: meta.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _userTile(AdminUser u) {
    final blocked = u.status == 'suspended';
    return RepaintBoundary(
      child: AdminPressable(
        lift: 1,
        pressedScale: 0.99,
        onTap: () => _openUserSheet(u),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
          decoration: adminCardDecoration(
            radius: 16,
            shadow: false,
            glow: blocked ? AdminColors.accentDanger : null,
          ),
          child: LayoutBuilder(
            builder: (context, c) => Row(
              children: [
                AdminAvatar(u.name, size: 40, colors: _userAvatarColors(u)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _userStatusPill(_userStatusMeta(u)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Hariri',
                  child: Material(
                    color: const Color(0x1A6366F1),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _openUserSheet(u),
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.edit_rounded,
                          size: 17,
                          color: Color(0xFF818CF8),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _userBlockButton(u, compact: c.maxWidth < 320),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _userBlockButton(AdminUser u, {bool compact = false}) {
    final blocked = u.status == 'suspended';
    final busy = _userBusy.contains(u.id);
    final color = blocked
        ? AdminColors.accentSuccess
        : AdminColors.accentDanger;
    final label = blocked
        ? (compact ? 'Fungua' : 'Fungua kifaa')
        : (compact ? 'Zuia' : 'Zuia kifaa');
    return Material(
      color: color.withValues(alpha: 0.12),
      shape: StadiumBorder(
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: busy ? null : () => unawaited(_toggleUserBlock(u)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: color,
                  ),
                )
              else
                Icon(
                  blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                  size: 14,
                  color: color,
                ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Blocks (after confirming) or unblocks the device. [onBusy] lets an open sheet repaint.
  Future<void> _toggleUserBlock(AdminUser u, {VoidCallback? onBusy}) async {
    if (_userBusy.contains(u.id)) return;
    final blocking = u.status != 'suspended';
    if (blocking) {
      final ok = await _showDeleteConfirmModal(
        title: 'Zuia kifaa hiki?',
        message:
            '"${u.name}" (${u.displayDeviceId}) hataweza kutazama channel yoyote hadi umfungue tena.',
        confirmLabel: 'Zuia kifaa',
      );
      if (!ok || !mounted) return;
    }
    setState(() => _userBusy.add(u.id));
    onBusy?.call();
    try {
      await _syncUserToBackend(u, {
        'status': blocking ? 'suspended' : 'active',
      });
      if (!mounted) return;
      _showToast(
        blocking
            ? 'Kifaa kimezuiwa — hakitaweza kutazama channel yoyote'
            : 'Kifaa kimefunguliwa',
        _ToastType.success,
      );
      unawaited(_searchUsersFromBackend(silent: true));
    } catch (e) {
      if (mounted) _showToast('Imeshindwa: $e', _ToastType.error);
    } finally {
      if (mounted) setState(() => _userBusy.remove(u.id));
      onBusy?.call();
    }
  }

  Future<void> _renameUser(AdminUser u) async {
    final n = (await _promptText('Badilisha jina', u.name))?.trim();
    if (n == null || n.isEmpty || n == u.name || !mounted) return;
    final old = u.name;
    setState(() => u.name = n);
    try {
      await _syncUserToBackend(u, {'name': n});
      if (mounted) _showToast('Jina limebadilishwa', _ToastType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => u.name = old);
      _showToast('Imeshindwa: $e', _ToastType.error);
    }
  }

  Widget _userSheetAction({
    required IconData icon,
    required String label,
    required Color color,
    String? hint,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: const Color(0x0DFFFFFF),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: enabled ? 0.16 : 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 17,
                    color: enabled ? color : const Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: enabled ? null : const Color(0xFF6B7280),
                        ),
                      ),
                      if (hint != null)
                        Text(
                          hint,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AdminColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Color(0xFF4B5563),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Everything the tile hides: device, phone, premium windows, and the edit actions.
  void _openUserSheet(AdminUser u) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AdminColors.bgSecondary,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final blocked = u.status == 'suspended';
          final busy = _userBusy.contains(u.id);
          void refresh() {
            if (ctx.mounted) setLocal(() {});
          }

          Future<void> run(Future<void> Function() action) async {
            await action();
            if (mounted) setState(() {});
            refresh();
          }

          Widget row(String label, String value, {bool copy = false}) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value.isEmpty ? '—' : value,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (copy && value.isNotEmpty)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: value));
                        _showToast('Imenakiliwa', _ToastType.success);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 15,
                          color: Color(0xFF818CF8),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }

          String window(DateTime? end) {
            if (end == null) return '';
            final local = end.toLocal();
            return local.isAfter(DateTime.now())
                ? '${_fmtAccessDate(local)} · ${_humanRemaining(local).toLowerCase()}'
                : '${_fmtAccessDate(local)} · imeisha';
          }

          final phone = u.phone.trim();
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      AdminAvatar(
                        u.name,
                        size: 52,
                        colors: _userAvatarColors(u),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              u.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _userStatusPill(_userStatusMeta(u)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Funga',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AdminColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: adminCardDecoration(radius: 16, shadow: false),
                    child: Column(
                      children: [
                        row('Device ID', u.displayDeviceId, copy: true),
                        row(
                          'Simu',
                          phone.toUpperCase() == 'N/A' ? '' : phone,
                          copy: true,
                        ),
                        row('Premium ya malipo', window(u.premiumUntil)),
                        row('Muda wa msimamizi', window(u.adminAccessUntil)),
                        row(
                          'Alijiunga',
                          '${_fmtDate(u.createdAt.toLocal())} · ${adminTimeAgo(u.createdAt)}',
                        ),
                        row('USR ID', u.id, copy: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'VITENDO',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _userSheetAction(
                    icon: Icons.edit_rounded,
                    label: 'Badilisha jina',
                    color: _freeColor,
                    onTap: () => run(() => _renameUser(u)),
                  ),
                  _userSheetAction(
                    icon: Icons.more_time_rounded,
                    label: 'Ongeza muda wa premium',
                    hint: blocked ? 'Fungua kifaa kwanza' : null,
                    color: AdminColors.accentSuccess,
                    onTap: blocked
                        ? null
                        : () => run(() => _showGrantAccessDialog(u)),
                  ),
                  _userSheetAction(
                    icon: Icons.notifications_active_outlined,
                    label: 'Tuma arifa kwa mtumiaji huyu',
                    color: _freeColor,
                    onTap: () {
                      Navigator.pop(ctx);
                      _modalSendNotification(deviceId: u.displayDeviceId);
                    },
                  ),
                  if (u.effectivePremium)
                    _userSheetAction(
                      icon: Icons.remove_circle_outline_rounded,
                      label: 'Ondoa premium',
                      hint: 'Malipo na muda wa msimamizi vitaondolewa',
                      color: AdminColors.accentDanger,
                      onTap: () => run(() => _revokeAllPremiumAccess(u)),
                    ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => run(() => _toggleUserBlock(u, onBusy: refresh)),
                    style: FilledButton.styleFrom(
                      backgroundColor: blocked
                          ? AdminColors.accentSuccess
                          : AdminColors.accentDanger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            blocked
                                ? Icons.lock_open_rounded
                                : Icons.block_rounded,
                            size: 18,
                          ),
                    label: Text(
                      blocked ? 'Fungua kifaa' : 'Zuia kifaa',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (!blocked) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Kifaa kilichozuiwa hakiwezi kutazama channel yoyote, hata kikiwa na premium.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _humanRemaining(DateTime end) {
    final d = end.difference(DateTime.now());
    if (d.isNegative) return 'Imeisha';
    if (d.inDays >= 1) return 'Bado siku ${d.inDays}, saa ${d.inHours % 24}';
    if (d.inHours >= 1) return 'Bado saa ${d.inHours}';
    if (d.inMinutes >= 1) return 'Bado dakika ${d.inMinutes}';
    return 'Dakika chache';
  }

  String _fmtAccessDate(DateTime d) {
    String t(int n) => n.toString().padLeft(2, '0');
    return '${t(d.day)}/${t(d.month)}/${d.year} ${t(d.hour)}:${t(d.minute)}';
  }

  void _applyServerUserFields(AdminUser u, Map<String, dynamic> j) {
    final name = _s(j['name']);
    if (name.isNotEmpty) u.name = name;
    final status = _s(j['status']);
    if (status.isNotEmpty) u.status = status;
    final sub = _s(j['subscription']);
    if (sub.isNotEmpty) u.subscription = sub;
    // Always overwrite dates — null from server means access was removed.
    if (j.containsKey('premium_until')) {
      u.premiumUntil = _dt(j['premium_until']);
    }
    if (j.containsKey('admin_access_until')) {
      u.adminAccessUntil = _dt(j['admin_access_until']);
    }
  }

  Future<void> _syncUserToBackend(
    AdminUser u,
    Map<String, dynamic> patch,
  ) async {
    if (!_hasAdminSession) return;
    final res = await http
        .patch(
          Uri.parse('$_apiBase/api/v1/admin/users/${u.id}'),
          headers: _adminHeaders(),
          body: jsonEncode(patch),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('user sync failed ${res.statusCode}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final userJson = map['user'];
    if (userJson is Map) {
      _applyServerUserFields(u, userJson.cast<String, dynamic>());
    }
  }

  Future<void> _revokeAllPremiumAccess(
    AdminUser u, {
    bool confirm = true,
  }) async {
    if (!_hasAdminSession) {
      _showToast('Hakuna login cha msimamizi', _ToastType.error);
      return;
    }
    if (confirm) {
      final ok = await _showDeleteConfirmModal(
        title: 'Ondoa ufikiaji wa premium?',
        message:
            'Mtumiaji "${u.name}" atapoteza ufikiaji wote wa premium (muda wa msimamizi na malipo). Hatua hii haiwezi kutenduliwa kwa urahisi.',
        confirmLabel: 'Ondoa premium',
      );
      if (!ok || !mounted) return;
    }
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/v1/admin/users/${u.id}/revoke-premium'),
            headers: _adminHeadersForDelete(),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final body = res.body.trim();
        final detail = body.isNotEmpty && body.length < 200
            ? body
            : 'HTTP ${res.statusCode}';
        _showToast('Imeshindwa kuondoa premium: $detail', _ToastType.error);
        return;
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final userJson = map['user'];
      setState(() {
        u.subscription = 'free';
        u.premiumUntil = null;
        u.adminAccessUntil = null;
        if (userJson is Map) {
          _applyServerUserFields(u, userJson.cast<String, dynamic>());
        }
      });
      _showToast('Premium imeondolewa kwa ${u.name}', _ToastType.success);
    } on Exception catch (e) {
      if (!mounted) return;
      _showToast('Imeshindwa: $e', _ToastType.error);
    }
  }

  Future<({List<AdminUser> users, int matched, int total, int? premiumTotal})>
  _fetchUsersForBulkRevoke({
    required String query,
    required bool premiumOnly,
  }) async {
    final q = query.trim();
    final res = await http
        .get(
          Uri.parse('$_apiBase/api/v1/admin/users').replace(
            queryParameters: {
              'limit': premiumOnly ? '2000' : '2000',
              if (premiumOnly) 'premium': '1',
              if (q.isNotEmpty) 'q': q,
            },
          ),
          headers: _adminHeaders(),
        )
        .timeout(const Duration(seconds: 20));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('users ${res.statusCode}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final rawUsers = map['users'];
    var users = rawUsers is List ? _parseUsersJson(rawUsers) : <AdminUser>[];
    final serverPremiumOnly = map['premium_only'] == true;

    // Older backends ignore ?premium=1 — enrich from /subscriptions (active only).
    if (premiumOnly && !serverPremiumOnly) {
      try {
        final subRes = await http
            .get(
              Uri.parse('$_apiBase/api/v1/admin/subscriptions'),
              headers: _adminHeaders(),
            )
            .timeout(const Duration(seconds: 20));
        if (subRes.statusCode >= 200 && subRes.statusCode < 300) {
          final subMap = jsonDecode(subRes.body) as Map<String, dynamic>;
          final rawSubs = subMap['subscriptions'];
          if (rawSubs is List) {
            final byId = {for (final u in users) u.id: u};
            for (final row in rawSubs.whereType<Map>()) {
              final j = row.cast<String, dynamic>();
              final status = _s(j['status']).toLowerCase();
              if (status != 'active') continue;
              final id = _s(j['id']);
              if (id.isEmpty) continue;
              final existing = byId[id];
              if (existing != null) {
                if (!existing.effectivePremium) {
                  existing.premiumUntil =
                      _dt(j['end_date']) ?? existing.premiumUntil;
                }
                continue;
              }
              byId[id] = AdminUser(
                id: id,
                name: _s(j['user_name'], fallback: 'Viewer'),
                phone: '—',
                deviceId: null,
                status: 'active',
                subscription: 'premium',
                createdAt:
                    _dt(j['created_at']) ??
                    DateTime.fromMillisecondsSinceEpoch(0),
                // Subscriptions API marks active via paid OR admin window; end_date is paid only.
                premiumUntil:
                    _dt(j['end_date']) ??
                    DateTime.now().add(const Duration(hours: 1)),
              );
            }
            users = byId.values.toList();
          }
        }
      } catch (_) {
        // Keep users list from /admin/users if subscriptions fails.
      }
    }

    // Client-side safety net: keep only users who still look premium when filtering.
    var filtered = premiumOnly
        ? users.where((u) => u.effectivePremium).toList()
        : users;
    if (q.isNotEmpty) {
      final needle = q.toLowerCase();
      final compact = needle.replaceAll(RegExp(r'[\s\-_.]+'), '');
      filtered = filtered.where((u) {
        final hay = '${u.name} ${u.phone} ${u.displayDeviceId} ${u.id}'
            .toLowerCase();
        if (hay.contains(needle)) return true;
        if (compact.length >= 4) {
          final compactHay = hay.replaceAll(RegExp(r'[\s\-_.]+'), '');
          if (compactHay.contains(compact)) return true;
        }
        return false;
      }).toList();
    }
    filtered.sort((a, b) {
      final c = b.createdAt.compareTo(a.createdAt);
      if (c != 0) return c;
      return b.id.compareTo(a.id);
    });
    final matchedRaw = map['matched'];
    final totalRaw = map['total'] ?? map['users_total'];
    final premiumRaw = map['premium_total'];
    int asInt(Object? v, int fallback) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    return (
      users: filtered,
      matched: premiumOnly || q.isNotEmpty
          ? filtered.length
          : asInt(matchedRaw, filtered.length),
      total: asInt(totalRaw, filtered.length),
      premiumTotal: premiumRaw == null
          ? (premiumOnly ? filtered.length : null)
          : asInt(premiumRaw, filtered.length),
    );
  }

  Future<int> _bulkRevokePremiumIds(Set<String> ids) async {
    if (ids.isEmpty) return 0;
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/v1/admin/users/bulk-revoke-premium'),
            headers: _adminHeaders(),
            body: jsonEncode({'user_ids': ids.toList()}),
          )
          .timeout(const Duration(seconds: 45));
      if (res.statusCode == 404) {
        // Older API builds may not have the bulk route yet — fall back per user.
        return _bulkRevokePremiumIdsSequentially(ids);
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        final body = res.body.trim();
        final detail = body.isNotEmpty && body.length < 220
            ? body
            : 'HTTP ${res.statusCode}';
        throw Exception(detail);
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final revokedCount = () {
        final v = map['revoked_count'];
        if (v is int) return v;
        if (v is num) return v.toInt();
        return ids.length;
      }();
      final revokedRaw = map['users'];
      final revokedIds = <String>{};
      if (revokedRaw is List) {
        for (final row in revokedRaw) {
          if (row is Map) {
            final id = _s(row['id']);
            if (id.isNotEmpty) revokedIds.add(id);
          }
        }
      }
      if (revokedIds.isEmpty) revokedIds.addAll(ids);

      if (mounted) {
        setState(() {
          for (final u in _users) {
            if (!revokedIds.contains(u.id)) continue;
            u.subscription = 'free';
            u.premiumUntil = null;
            u.adminAccessUntil = null;
          }
        });
      }
      return revokedCount;
    } on Exception {
      rethrow;
    }
  }

  Future<int> _bulkRevokePremiumIdsSequentially(Set<String> ids) async {
    var ok = 0;
    final revokedIds = <String>{};
    for (final id in ids) {
      final res = await http
          .post(
            Uri.parse(
              '$_apiBase/api/v1/admin/users/${Uri.encodeComponent(id)}/revoke-premium',
            ),
            headers: _adminHeadersForDelete(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ok += 1;
        revokedIds.add(id);
      }
    }
    if (mounted && revokedIds.isNotEmpty) {
      setState(() {
        for (final u in _users) {
          if (!revokedIds.contains(u.id)) continue;
          u.subscription = 'free';
          u.premiumUntil = null;
          u.adminAccessUntil = null;
        }
      });
    }
    if (ok == 0 && ids.isNotEmpty) {
      throw Exception('Imeshindwa kuondoa premium (HTTP fallback)');
    }
    return ok;
  }

  Future<void> _showBulkRevokePremiumDialog() async {
    if (!_hasAdminSession) {
      _showToast('Hujaingia (login) kama msimamizi', _ToastType.error);
      return;
    }

    final searchCtrl = TextEditingController();
    Timer? debounce;
    var loading = true;
    var acting = false;
    var premiumOnly = true;
    var query = '';
    var users = <AdminUser>[];
    var matched = 0;
    var total = 0;
    int? premiumTotal;
    final selected = <String>{};
    String? error;
    var initialLoadScheduled = false;
    void Function(void Function())? dialogSetState;

    Future<void> load([void Function(void Function())? setModal]) async {
      final set = setModal ?? dialogSetState;
      if (set == null) return;
      set(() {
        loading = true;
        error = null;
      });
      try {
        final result = await _fetchUsersForBulkRevoke(
          query: query,
          premiumOnly: premiumOnly,
        );
        if (!mounted) return;
        set(() {
          users = result.users;
          matched = result.matched;
          total = result.total;
          premiumTotal = result.premiumTotal;
          loading = false;
          // Drop selections that vanished from the list after a refresh.
          selected.removeWhere((id) => !users.any((u) => u.id == id));
        });
      } catch (e) {
        if (!mounted) return;
        set(() {
          loading = false;
          error = '$e';
          users = [];
        });
      }
    }

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModal) {
            dialogSetState = setModal;
            if (!initialLoadScheduled) {
              initialLoadScheduled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (ctx.mounted) unawaited(load(setModal));
              });
            }

            final visibleIds = users.map((u) => u.id).toSet();
            final allVisibleSelected =
                visibleIds.isNotEmpty && visibleIds.every(selected.contains);
            final selectedCount = selected.length;

            String sourceLabel(AdminUser u) {
              final paid =
                  u.premiumUntil != null &&
                  u.premiumUntil!.isAfter(DateTime.now());
              final adm = u.adminAccessActive;
              if (paid && adm) return 'Malipo + msimamizi';
              if (paid) return 'Malipo';
              if (adm) return 'Msimamizi';
              if (u.subscription == 'premium') return 'Premium (flag)';
              return 'Free';
            }

            String expiryLabel(AdminUser u) {
              final ends = <DateTime>[
                if (u.premiumUntil != null &&
                    u.premiumUntil!.isAfter(DateTime.now()))
                  u.premiumUntil!,
                if (u.adminAccessUntil != null &&
                    u.adminAccessUntil!.isAfter(DateTime.now()))
                  u.adminAccessUntil!,
              ];
              if (ends.isEmpty) return '—';
              ends.sort();
              return 'hadi ${_fmtAccessDate(ends.last)}';
            }

            return AlertDialog(
              backgroundColor: AdminColors.bgSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              title: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0x33F43F5E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person_off_rounded,
                      color: Color(0xFFFB7185),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ondoa premium',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Chagua watumiaji — watarudishwa free na watalipa tena',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AdminColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Funga',
                    onPressed: acting ? null : () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              content: SizedBox(
                width: min(640, MediaQuery.sizeOf(ctx).width - 32),
                height: min(560, MediaQuery.sizeOf(ctx).height * 0.72),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      enabled: !acting,
                      onChanged: (v) {
                        debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 320), () {
                          query = v.trim();
                          unawaited(load(setModal));
                        });
                      },
                      textInputAction: TextInputAction.search,
                      decoration: _inputDeco().copyWith(
                        hintText: 'Tafuta: jina, simu, Device ID, USR-…',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: loading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : (searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      tooltip: 'Futa',
                                      icon: const Icon(
                                        Icons.clear_rounded,
                                        size: 18,
                                      ),
                                      onPressed: acting
                                          ? null
                                          : () {
                                              searchCtrl.clear();
                                              query = '';
                                              unawaited(load(setModal));
                                            },
                                    )
                                  : IconButton(
                                      tooltip: 'Onyesha upya',
                                      icon: const Icon(
                                        Icons.refresh_rounded,
                                        size: 18,
                                      ),
                                      onPressed: acting
                                          ? null
                                          : () => unawaited(load(setModal)),
                                    )),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilterChip(
                          selected: premiumOnly,
                          label: Text(
                            premiumTotal != null
                                ? 'Premium tu ($premiumTotal)'
                                : 'Premium tu',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onSelected: acting
                              ? null
                              : (v) {
                                  if (!v) return;
                                  premiumOnly = true;
                                  setModal(() {});
                                  unawaited(load(setModal));
                                },
                          selectedColor: const Color(0x33FBBF24),
                          checkmarkColor: const Color(0xFFFBBF24),
                          side: BorderSide(
                            color: premiumOnly
                                ? const Color(0x66FBBF24)
                                : const Color(0x22FFFFFF),
                          ),
                        ),
                        FilterChip(
                          selected: !premiumOnly,
                          label: Text(
                            'Wote ($total)',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onSelected: acting
                              ? null
                              : (v) {
                                  if (!v) return;
                                  premiumOnly = false;
                                  setModal(() {});
                                  unawaited(load(setModal));
                                },
                          selectedColor: const Color(0x336366F1),
                          checkmarkColor: const Color(0xFFA5B4FC),
                          side: BorderSide(
                            color: !premiumOnly
                                ? const Color(0x666366F1)
                                : const Color(0x22FFFFFF),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: acting || users.isEmpty
                              ? null
                              : () => setModal(() {
                                  if (allVisibleSelected) {
                                    selected.removeAll(visibleIds);
                                  } else {
                                    selected.addAll(visibleIds);
                                  }
                                }),
                          icon: Icon(
                            allVisibleSelected
                                ? Icons.deselect_rounded
                                : Icons.select_all_rounded,
                            size: 16,
                          ),
                          label: Text(
                            allVisibleSelected
                                ? 'Ondoa uteuzi'
                                : 'Chagua vyote vinavyoonekana',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loading
                          ? 'Inapakia orodha…'
                          : error != null
                          ? 'Hitilafu: $error'
                          : '${users.length} wanaonekana · $matched matokeo'
                                '${selectedCount > 0 ? ' · $selectedCount wamechaguliwa' : ''}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: error != null
                            ? const Color(0xFFFB7185)
                            : AdminColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AdminColors.bgPrimary,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0x14FFFFFF)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: loading && users.isEmpty
                            ? const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            : users.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    premiumOnly
                                        ? 'Hakuna watumiaji wa premium wanaolingana.'
                                        : 'Hakuna watumiaji wanaolingana.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: AdminColors.textSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: users.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  color: Color(0x12FFFFFF),
                                ),
                                itemBuilder: (context, i) {
                                  final u = users[i];
                                  final checked = selected.contains(u.id);
                                  final premium = u.effectivePremium;
                                  return CheckboxListTile(
                                    value: checked,
                                    onChanged: acting
                                        ? null
                                        : (v) => setModal(() {
                                            if (v == true) {
                                              selected.add(u.id);
                                            } else {
                                              selected.remove(u.id);
                                            }
                                          }),
                                    dense: true,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    activeColor: const Color(0xFFF43F5E),
                                    title: Text(
                                      u.name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${u.phone} · ${u.displayDeviceId}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AdminColors.textSecondary,
                                              height: 1.25,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${premium ? 'PREMIUM' : 'FREE'} · ${sourceLabel(u)} · ${expiryLabel(u)}',
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: premium
                                                  ? const Color(0xFFFBBF24)
                                                  : AdminColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: acting ? null : () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AdminColors.textSecondary,
                          side: const BorderSide(color: Color(0x26FFFFFF)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Ghairi'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: acting || selected.isEmpty
                            ? null
                            : () async {
                                final ok = await _showDeleteConfirmModal(
                                  title:
                                      'Rudisha free $selectedCount watumiaji?',
                                  message:
                                      'Watumiaji $selectedCount wataondolewa premium (malipo + muda wa msimamizi). '
                                      'Watakuwa free tena na watalazimika kulipa ili kuona channels za premium.',
                                  confirmLabel: 'Ondoa premium',
                                );
                                if (!ok || !ctx.mounted) return;
                                setModal(() => acting = true);
                                try {
                                  final n = await _bulkRevokePremiumIds(
                                    Set<String>.from(selected),
                                  );
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  if (!mounted) return;
                                  _showToast(
                                    n == 1
                                        ? 'Premium imeondolewa kwa mtumiaji 1'
                                        : 'Premium imeondolewa kwa watumiaji $n',
                                    _ToastType.success,
                                  );
                                  unawaited(_searchUsersFromBackend());
                                  unawaited(_refreshDashboardStats());
                                } catch (e) {
                                  if (!ctx.mounted) return;
                                  setModal(() => acting = false);
                                  _showToast(
                                    'Imeshindwa: $e',
                                    _ToastType.error,
                                  );
                                }
                              },
                        icon: acting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.person_off_rounded, size: 18),
                        label: Text(
                          acting
                              ? 'Inaondoa…'
                              : selectedCount == 0
                              ? 'Chagua watumiaji'
                              : 'Ondoa premium ($selectedCount)',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );
    } finally {
      debounce?.cancel();
      searchCtrl.dispose();
    }
  }

  Future<void> _applyAdminDuration(AdminUser u, Duration add) async {
    if (!_hasAdminSession) return;
    if (add.inMilliseconds < 1000) return;
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/v1/admin/users/${u.id}/grant-access'),
            headers: _adminHeaders(),
            body: jsonEncode({'duration_ms': add.inMilliseconds}),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('grant failed ${res.statusCode}');
      }
      final map = jsonDecode(res.body) as Map<String, dynamic>;
      final userJson = map['user'];
      if (!mounted) return;
      setState(() {
        if (userJson is Map) {
          _applyServerUserFields(u, userJson.cast<String, dynamic>());
        }
      });
      final end = u.adminAccessUntil;
      _showToast(
        end != null
            ? 'Premium hadi ${_fmtAccessDate(end)}'
            : 'Muda wa premium umeongezwa',
        _ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      _showToast('Imeshindwa: $e', _ToastType.error);
    }
  }

  Future<void> _clearAdminAccess(AdminUser u) async {
    try {
      await _syncUserToBackend(u, {'admin_access_until': null});
      if (!mounted) return;
      setState(() {});
      _showToast('Muda wa msimamizi umeondolewa', _ToastType.info);
    } catch (e) {
      if (!mounted) return;
      _showToast('Imeshindwa: $e', _ToastType.error);
    }
  }

  Future<bool> _showDeleteConfirmModal({
    required String title,
    required String message,
    String confirmLabel = 'Futa',
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.bgSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(message, style: const TextStyle(height: 1.35)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ghairi'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _showGrantAccessDialog(AdminUser u) async {
    final customAmount = TextEditingController(text: '1');
    var unit = _AccessUnit.days;

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModal) => AlertDialog(
            backgroundColor: AdminColors.bgSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Pa premium kwa muda',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mtumiaji: ${u.name}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      'Device ID: ${u.displayDeviceId}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      u.adminAccessActive
                          ? 'Muda wa sasa wa msimamizi unaisha: ${_fmtAccessDate(u.adminAccessUntil!)}. Mpya utaongezwa juu ya hii.'
                          : 'Hakuna muda wa msimamizi unaofanya kazi. Unaanza kutoka sasa.',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AdminColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Vinjari haraka',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _presetChip(ctx, u, 'Saa 1', const Duration(hours: 1)),
                        _presetChip(
                          ctx,
                          u,
                          'Masaa 6',
                          const Duration(hours: 6),
                        ),
                        _presetChip(ctx, u, 'Siku 1', const Duration(days: 1)),
                        _presetChip(ctx, u, 'Siku 7', const Duration(days: 7)),
                        _presetChip(
                          ctx,
                          u,
                          'Siku 30',
                          const Duration(days: 30),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Maongezi ya kujitegemea',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 72,
                          child: TextField(
                            controller: customAmount,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(fontSize: 13),
                            decoration: _inputDeco().copyWith(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<_AccessUnit>(
                            isExpanded: true,
                            value: unit,
                            dropdownColor: AdminColors.bgSecondary,
                            decoration: _inputDeco(),
                            items: const [
                              DropdownMenuItem(
                                value: _AccessUnit.hours,
                                child: Text('Saa'),
                              ),
                              DropdownMenuItem(
                                value: _AccessUnit.days,
                                child: Text('Siku'),
                              ),
                              DropdownMenuItem(
                                value: _AccessUnit.weeks,
                                child: Text('Wiki'),
                              ),
                              DropdownMenuItem(
                                value: _AccessUnit.months,
                                child: Text('Mwezi (30 siku)'),
                              ),
                            ],
                            onChanged: (v) => setModal(() => unit = v ?? unit),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: u.adminAccessUntil != null
                    ? () async {
                        final ok = await _showDeleteConfirmModal(
                          title: 'Futa muda wa msimamizi?',
                          message:
                              'Muda wa premium uliopewa na msimamizi kwa “${u.name}” utaondolewa. Malipo ya mfumo yatabaki ikiwa yapo.',
                        );
                        if (!mounted || !ok) return;
                        await _clearAdminAccess(u);
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    : null,
                child: const Text('Futa muda wa msimamizi'),
              ),
              if (u.effectivePremium)
                TextButton(
                  onPressed: () async {
                    final ok = await _showDeleteConfirmModal(
                      title: 'Ondoa premium kabisa?',
                      message:
                          '“${u.name}” atapoteza ufikiaji wote wa premium (msimamizi na malipo).',
                      confirmLabel: 'Ondoa premium',
                    );
                    if (!mounted || !ok) return;
                    try {
                      await _revokeAllPremiumAccess(u, confirm: false);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      if (!mounted) return;
                      _showToast('Imeshindwa: $e', _ToastType.error);
                    }
                  },
                  child: const Text(
                    'Ondoa premium kabisa',
                    style: TextStyle(color: Color(0xFFEF4444)),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Funga'),
              ),
              FilledButton(
                onPressed: () async {
                  final n = int.tryParse(customAmount.text.trim()) ?? 1;
                  if (n < 1) return;
                  final add = _durationFromUnit(n, unit);
                  await _applyAdminDuration(u, add);
                  Navigator.pop(ctx);
                },
                child: const Text('Ongeza muda'),
              ),
            ],
          ),
        ),
      );
    } finally {
      customAmount.dispose();
    }
  }

  Widget _presetChip(BuildContext ctx, AdminUser u, String label, Duration d) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () async {
        await _applyAdminDuration(u, d);
        Navigator.pop(ctx);
      },
      backgroundColor: const Color(0xFF1A2332),
      side: const BorderSide(color: Color(0x33FFFFFF)),
    );
  }

  Duration _durationFromUnit(int n, _AccessUnit unit) {
    switch (unit) {
      case _AccessUnit.hours:
        return Duration(hours: n);
      case _AccessUnit.days:
        return Duration(days: n);
      case _AccessUnit.weeks:
        return Duration(days: 7 * n);
      case _AccessUnit.months:
        return Duration(days: 30 * n);
    }
  }

  Future<String?> _promptText(String title, String initial) async {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.bgSecondary,
        title: Text(title),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ghairi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // --- Channels ---
  Widget _pageChannels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AdminPageHeading('Chaneli'),
                  Text(
                    '${_channels.length} channels',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            _btnPrimary(
              label: 'Ongeza',
              icon: Icons.add,
              small: true,
              onTap: () => _showChannelEditor(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final cross = c.maxWidth > 900 ? 4 : (c.maxWidth > 520 ? 3 : 2);
              final tileW = (c.maxWidth - (cross - 1) * 12) / cross;
              final cacheW = (tileW * MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(64, 512);
              if (_channels.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 48),
                    Icon(
                      Icons.tv_off_outlined,
                      size: 40,
                      color: AdminColors.textSecondary,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Hakuna chaneli',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                  ],
                );
              }
              return GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemCount: _channels.length,
                itemBuilder: (context, i) {
                  final ch = _channels[i];
                  return RepaintBoundary(
                    child: Container(
                      decoration: adminCardDecoration(),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  _safeImageUrl(ch.thumbnail),
                                  fit: BoxFit.cover,
                                  cacheWidth: cacheW,
                                  filterQuality: FilterQuality.low,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) =>
                                      _imageFallback(Icons.tv, 'Hakuna picha'),
                                ),
                                if (ch.status != 'active')
                                  Positioned.fill(
                                    child: Container(
                                      color: const Color(0x66000000),
                                      alignment: Alignment.center,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xE61F2937),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Text(
                                          'IMEZIMWA',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.8,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (ch.premium)
                                        _tinyBadge(
                                          'Premium',
                                          const Color(0xFFF59E0B),
                                          darkText: true,
                                        ),
                                      if (ch.live) ...[
                                        const SizedBox(width: 4),
                                        _tinyBadge(
                                          'LIVE',
                                          const Color(0xFFEF4444),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (ch.effectiveDrm != 'none')
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: _tinyBadge(
                                      _channelDrmShort(ch.effectiveDrm),
                                      const Color(0xFF4F46E5),
                                    ),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Color(0x00000000),
                                          Color(0xCC000000),
                                        ],
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ch.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          ch.streamUrl.trim().isNotEmpty
                                              ? '${ch.category} · Stream'
                                              : ch.category,
                                          style: const TextStyle(
                                            fontSize: 9,
                                            color: Color(0xFFD1D5DB),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(6, 2, 4, 6),
                            child: Row(
                              children: [
                                Text(
                                  '⭐${ch.rating}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: AdminColors.textSecondary,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () => _showChannelEditor(index: i),
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                    color: Color(0xFF818CF8),
                                  ),
                                  tooltip: 'Hariri chaneli',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  onPressed: () => _confirmDeleteChannel(ch.id),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Color(0xFFF87171),
                                  ),
                                  tooltip: 'Futa chaneli',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // --- Slides ---
  Widget _pageSlides() {
    final slides = [..._slides]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final activeCount = slides.where((s) => s.active).length;
    final premiumCount = slides.where((s) => s.premium).length;
    final slideQuery = _slideQuery ?? '';
    final slideFilter = _slideFilter ?? 'all';
    final q = slideQuery.trim().toLowerCase();
    final filtered = slides.where((s) {
      final byQuery =
          q.isEmpty ||
          s.title.toLowerCase().contains(q) ||
          s.subtitle.toLowerCase().contains(q) ||
          s.id.toLowerCase().contains(q);
      final byFilter = switch (slideFilter) {
        'active' => s.active,
        'inactive' => !s.active,
        'premium' => s.premium,
        _ => true,
      };
      return byQuery && byFilter;
    }).toList();

    /// Full list visible only with no filters — reorder updates `sort_order` on all slides.
    final canReorderSlides =
        q.isEmpty && slideFilter == 'all' && filtered.length >= 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// Dev-only banner: release IPAs/APKs built with [--dart-define-from-file] omit this panel.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0xFF0F1419),
            border: Border.all(color: const Color(0x226366F1)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mabango',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Carousel ya app · haraka kuscan',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AdminColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _btnPrimary(
                    label: 'Ongeza',
                    icon: Icons.add_rounded,
                    small: true,
                    onTap: () => _showSlideEditor(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _slideMetricPill(
                    'Total',
                    '${slides.length}',
                    const Color(0xFF818CF8),
                  ),
                  _slideMetricPill(
                    'Active',
                    '$activeCount',
                    const Color(0xFF34D399),
                  ),
                  _slideMetricPill(
                    'Premium',
                    '$premiumCount',
                    const Color(0xFFFBBF24),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _slideQuery = v),
                decoration: _inputDeco().copyWith(
                  isDense: true,
                  hintText: 'Tafuta…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _slideFilterChip('all', 'All'),
                _slideFilterChip('active', 'Active'),
                _slideFilterChip('inactive', 'Off'),
                _slideFilterChip('premium', 'Pro'),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (!canReorderSlides && filtered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Weka filtari "All" na uondoe utafutaji ili kupanga slides kwa kuvuta kinara.',
              style: TextStyle(
                fontSize: 11,
                height: 1.35,
                color: AdminColors.textSecondary.withValues(alpha: 0.95),
              ),
            ),
          ),
        if (filtered.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AdminColors.bgTertiary,
              border: Border.all(color: const Color(0x14FFFFFF)),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.photo_library_outlined,
                  size: 28,
                  color: Color(0xFF64748B),
                ),
                SizedBox(height: 8),
                Text(
                  'Hakuna slide',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                SizedBox(height: 4),
                Text(
                  'Badilisha filtari au ongeza mpya',
                  style: TextStyle(
                    fontSize: 11,
                    color: AdminColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else if (canReorderSlides)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final t = Curves.easeOut.transform(animation.value);
                  return Transform.scale(
                    scale: 1.0 + 0.02 * t,
                    child: Material(
                      elevation: 8 * t,
                      shadowColor: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.transparent,
                      child: child,
                    ),
                  );
                },
              );
            },
            itemCount: filtered.length,
            onReorder: _onSlidesListReorder,
            itemBuilder: (context, i) {
              final s = filtered[i];
              final sourceIndex = _slides.indexWhere((e) => e.id == s.id);
              final bottom = i < filtered.length - 1 ? 8.0 : 0.0;
              return Padding(
                key: ValueKey(s.id),
                padding: EdgeInsets.only(bottom: bottom),
                child: _slideListRow(
                  s,
                  sourceIndex,
                  listIndex: i,
                  showDragHandle: true,
                ),
              );
            },
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = filtered[i];
              final sourceIndex = _slides.indexWhere((e) => e.id == s.id);
              return _slideListRow(
                s,
                sourceIndex,
                listIndex: i,
                showDragHandle: false,
              );
            },
          ),
      ],
    );
  }

  /// Single slide row — optional [ReorderableDragStartListener] via [showDragHandle] + [listIndex].
  Widget _slideListRow(
    AdminSlide s,
    int sourceIndex, {
    required int listIndex,
    required bool showDragHandle,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: sourceIndex < 0
            ? null
            : () => _showSlideEditor(index: sourceIndex),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: const Color(0xFF151A22),
            border: Border.all(color: const Color(0x1EFFFFFF)),
          ),
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showDragHandle)
                ReorderableDragStartListener(
                  index: listIndex,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        size: 22,
                        color: AdminColors.textSecondary.withValues(
                          alpha: 0.75,
                        ),
                      ),
                    ),
                  ),
                ),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 120,
                  height: 67,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        _safeImageUrl(s.imageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _slideThumbFallback(Icons.broken_image_outlined),
                      ),
                      if (!s.active)
                        Container(
                          color: const Color(0x77000000),
                          alignment: Alignment.center,
                          child: const Text(
                            'IMEZIMWA',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                    if (s.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          s.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AdminColors.textSecondary,
                            height: 1.2,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _tinyBadge('#${s.sortOrder}', const Color(0xFF334155)),
                        _tinyBadge(
                          s.premium ? 'PRO' : 'FREE',
                          s.premium
                              ? const Color(0xFFEAB308)
                              : const Color(0xFF475569),
                          darkText: s.premium,
                        ),
                        if (!s.active)
                          _tinyBadge('Inactive', const Color(0xFFBE123C)),
                        Text(
                          s.id,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: AdminColors.textSecondary.withValues(
                              alpha: 0.85,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Hariri',
                    onPressed: sourceIndex < 0
                        ? null
                        : () => _showSlideEditor(index: sourceIndex),
                    icon: const Icon(
                      Icons.edit_rounded,
                      size: 18,
                      color: Color(0xFF93C5FD),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0x146366F1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Futa',
                    onPressed: () => _confirmDeleteSlide(s.id),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 18,
                      color: Color(0xFFFCA5A5),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0x14EF4444),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSlidesListReorder(int oldIndex, int newIndex) {
    var newIdx = newIndex;
    if (newIdx > oldIndex) newIdx--;
    if (oldIndex == newIdx) return;
    final ordered = [..._slides]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIdx, moved);
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].sortOrder = i + 1;
    }
    setState(() => _slides = ordered);
    unawaited(_persistSlideSortOrders(ordered));
  }

  Future<void> _persistSlideSortOrders(List<AdminSlide> ordered) async {
    if (!_hasAdminSession) return;
    try {
      final results = await Future.wait(
        ordered.map(
          (s) => http
              .patch(
                _adminSlideUri(s.id),
                headers: _adminHeaders(),
                body: jsonEncode({'sort_order': s.sortOrder}),
              )
              .timeout(const Duration(seconds: 12)),
        ),
      );
      for (final res in results) {
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('sort_order ${res.statusCode}');
        }
      }
    } catch (_) {
      if (mounted) {
        _showToast(
          'Mpangilio umebadilika hapa, lakini sync ya server imeshindikana.',
          _ToastType.warning,
        );
      }
    }
  }

  Widget _slideMetricPill(String label, String value, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF111827),
        border: Border.all(color: const Color(0x2294A3B8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AdminColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _slideThumbFallback(IconData icon) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
      ),
      child: Icon(icon, size: 24, color: const Color(0xFF64748B)),
    );
  }

  Widget _slideFilterChip(String id, String label) {
    final selected = (_slideFilter ?? 'all') == id;
    return ChoiceChip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      selected: selected,
      onSelected: (_) => setState(() => _slideFilter = id),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: selected ? const Color(0xFFE0E7FF) : const Color(0xFF94A3B8),
      ),
      selectedColor: const Color(0x334F46E5),
      backgroundColor: const Color(0x22111B2C),
      side: BorderSide(
        color: selected ? const Color(0x665B7CFA) : const Color(0x1FFFFFFF),
      ),
    );
  }

  String _nextSlideId() {
    var maxN = 0;
    for (final s in _slides) {
      final n = int.tryParse(s.id.replaceAll(RegExp(r'\D'), ''));
      if (n != null && n > maxN) maxN = n;
    }
    return 'SL-${(maxN + 1).toString().padLeft(3, '0')}';
  }

  Future<void> _confirmDeleteSlide(String slideId) async {
    final index = _slides.indexWhere((e) => e.id == slideId);
    if (index < 0) {
      if (mounted) _showToast('Slide haipatikani.', _ToastType.error);
      return;
    }
    final s = _slides[index];
    final ok = await _showDeleteConfirmModal(
      title: 'Futa slide?',
      message: '“${s.title}” itaondolewa kwenye app moja kwa moja.',
    );
    if (!ok || !mounted) return;

    final previousSlides = List<AdminSlide>.from(_slides);
    final id = slideId;

    if (_hasAdminSession) {
      try {
        final res = await http
            .delete(_adminSlideUri(id), headers: _adminHeadersForDelete())
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 404 &&
            (res.statusCode < 200 || res.statusCode >= 300)) {
          throw Exception(_adminHttpError(res));
        }
        if (!mounted) return;
        setState(() => _slides.removeWhere((e) => e.id == id));
        final refreshed = await _refreshSlidesFromServer();
        if (!refreshed) await _hydrateFromBackend();
        if (!mounted) return;
        _showToast('Slide imefutwa kwenye databesi', _ToastType.success);
      } catch (e) {
        if (!mounted) return;
        setState(() => _slides = previousSlides);
        _showToast('Kufuta slide kumeshindikana: $e', _ToastType.error);
      }
      return;
    }

    setState(() => _slides.removeWhere((e) => e.id == id));
    _showToast(
      'Imefutwa local pekee. Ingia ili kusawazisha na server.',
      _ToastType.warning,
    );
  }

  void _showSlideEditor({int? index}) {
    final existing = index != null ? _slides[index] : null;
    final isEdit = existing != null;
    final title = TextEditingController(text: existing?.title ?? '');
    final subtitle = TextEditingController(text: existing?.subtitle ?? '');
    final imageUrl = TextEditingController(text: existing?.imageUrl ?? '');
    var premium = existing?.premium ?? false;
    var active = existing?.active ?? true;
    final sortCtl = TextEditingController(
      text: '${existing?.sortOrder ?? (_slides.length + 1)}',
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          backgroundColor: AdminColors.bgSecondary,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 22,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(18, 14, 10, 0),
          contentPadding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          actionsPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0x186366F1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.slideshow_rounded,
                  size: 18,
                  color: Color(0xFFA5B4FC),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isEdit ? 'Hariri slide' : 'Slide mpya',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 340,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: imageUrl.text.trim().isEmpty
                          ? _slideThumbFallback(
                              Icons.add_photo_alternate_outlined,
                            )
                          : Image.network(
                              _safeImageUrl(imageUrl.text.trim()),
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AdminColors.accentPrimary
                                          .withValues(alpha: 0.8),
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => _slideThumbFallback(
                                Icons.hide_image_outlined,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: title,
                    style: const TextStyle(fontSize: 13),
                    decoration: _inputDeco().copyWith(
                      labelText: 'Kichwa',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: subtitle,
                    style: const TextStyle(fontSize: 13),
                    decoration: _inputDeco().copyWith(
                      labelText: 'Maelezo mafupi',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: imageUrl,
                    style: const TextStyle(fontSize: 12),
                    decoration: _inputDeco().copyWith(
                      labelText: 'URL ya picha',
                      hintText: 'https://…',
                      isDense: true,
                    ),
                    onChanged: (_) => setModal(() {}),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: sortCtl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 13),
                      decoration: _inputDeco().copyWith(
                        labelText: 'Mpangilio',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Ni slide ya premium',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    value: premium,
                    onChanged: (v) => setModal(() => premium = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Inaonekana kwenye app',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    value: active,
                    onChanged: (v) => setModal(() => active = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Ghairi',
                style: TextStyle(
                  fontSize: 13,
                  color: AdminColors.textSecondary,
                ),
              ),
            ),
            FilledButton(
              onPressed: () async {
                final t = title.text.trim();
                final st = subtitle.text.trim();
                final img = imageUrl.text.trim();
                final order =
                    int.tryParse(sortCtl.text.trim()) ?? (_slides.length + 1);
                if (t.isEmpty || img.isEmpty) {
                  _showToast('Jaza title na URL ya picha', _ToastType.error);
                  return;
                }
                if (!_hasAdminSession) {
                  _showToast(
                    'Ingia kwanza (skrini ya kwanza) ili kuhifadhi kwenye server.',
                    _ToastType.error,
                  );
                  return;
                }

                final payloadBody = <String, dynamic>{
                  'title': t,
                  'subtitle': st,
                  'image_url': img,
                  'premium': premium,
                  'active': active,
                  'sort_order': order,
                };

                try {
                  if (isEdit && index != null) {
                    final editIndex = index;
                    final id = _slides[editIndex].id;
                    final res = await http
                        .patch(
                          _adminSlideUri(id),
                          headers: _adminHeaders(),
                          body: jsonEncode(payloadBody),
                        )
                        .timeout(const Duration(seconds: 25));
                    if (res.statusCode < 200 || res.statusCode >= 300) {
                      throw Exception(
                        res.body.isNotEmpty
                            ? res.body
                            : 'HTTP ${res.statusCode}',
                      );
                    }
                    if (!mounted) return;
                    setState(() {
                      final s = _slides[editIndex];
                      s.title = t;
                      s.subtitle = st;
                      s.imageUrl = img;
                      s.premium = premium;
                      s.active = active;
                      s.sortOrder = order;
                    });
                  } else {
                    final newSlide = AdminSlide(
                      id: _nextSlideId(),
                      title: t,
                      subtitle: st,
                      imageUrl: img,
                      premium: premium,
                      active: active,
                      sortOrder: order,
                    );
                    final res = await http
                        .post(
                          Uri.parse('$_apiBase/api/v1/admin/slides'),
                          headers: _adminHeaders(),
                          body: jsonEncode({'id': newSlide.id, ...payloadBody}),
                        )
                        .timeout(const Duration(seconds: 25));
                    if (res.statusCode < 200 || res.statusCode >= 300) {
                      throw Exception(
                        res.body.isNotEmpty
                            ? res.body
                            : 'HTTP ${res.statusCode}',
                      );
                    }
                    if (!mounted) return;
                    setState(() => _slides.insert(0, newSlide));
                  }

                  if (!mounted) return;
                  Navigator.pop(ctx);
                  _showToast(
                    isEdit
                        ? 'Slide imehifadhiwa kwenye databesi'
                        : 'Slide imeongezwa kwenye databesi',
                    _ToastType.success,
                  );
                  unawaited(_hydrateFromBackend());
                } catch (e) {
                  if (!mounted) return;
                  _showToast(
                    'Imeshindikana kuhifadhi slide: $e',
                    _ToastType.error,
                  );
                }
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(isEdit ? 'Hifadhi' : 'Ongeza'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tinyBadge(String t, Color bg, {bool darkText = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: darkText ? const Color(0xFF111827) : Colors.white,
        ),
      ),
    );
  }

  String _safeImageUrl(String raw) {
    final u = raw.trim();
    if (u.startsWith('http://')) return 'https://${u.substring(7)}';
    return u;
  }

  Widget _imageFallback(IconData icon, String label) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2937), Color(0xFF111827)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF9CA3AF), size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }

  String _channelDrmShort(String drm) {
    return switch (drm) {
      'widevine' => 'WV',
      'clearkey' => 'CK',
      _ => '',
    };
  }

  String _nextChannelId() {
    var maxN = 0;
    for (final c in _channels) {
      final n = int.tryParse(c.id.replaceAll(RegExp(r'\D'), ''));
      if (n != null && n > maxN) maxN = n;
    }
    return 'CH-${(maxN + 1).toString().padLeft(4, '0')}';
  }

  Future<void> _confirmDeleteChannel(String channelId) async {
    final index = _channels.indexWhere((e) => e.id == channelId);
    if (index < 0) {
      if (mounted) _showToast('Chaneli haipatikani.', _ToastType.error);
      return;
    }
    final ch = _channels[index];
    final ok = await _showDeleteConfirmModal(
      title: 'Futa chaneli?',
      message: '“${ch.name}” itaondolewa kwenye app moja kwa moja.',
    );
    if (!ok || !mounted) return;
    final previous = List<AdminChannel>.from(_channels);
    final id = channelId;
    if (_hasAdminSession) {
      try {
        final res = await http
            .delete(_adminChannelUri(id), headers: _adminHeadersForDelete())
            .timeout(const Duration(seconds: 12));
        if (res.statusCode != 404 &&
            (res.statusCode < 200 || res.statusCode >= 300)) {
          throw Exception(_adminHttpError(res));
        }
        if (!mounted) return;
        setState(() => _channels.removeWhere((e) => e.id == id));
        final refreshed = await _refreshChannelsFromServer();
        if (!refreshed) await _hydrateFromBackend();
        if (!mounted) return;
        _showToast('Chaneli imefutwa kwenye databesi', _ToastType.success);
      } catch (e) {
        if (!mounted) return;
        setState(() => _channels = previous);
        _showToast('Kufuta chaneli kumeshindikana: $e', _ToastType.error);
      }
      return;
    }
    setState(() => _channels.removeWhere((e) => e.id == id));
    _showToast(
      'Imefutwa local pekee. Ingia ili kusawazisha na server.',
      _ToastType.warning,
    );
  }

  void _showChannelEditor({int? index}) {
    final existing = index != null ? _channels[index] : null;
    final isEdit = existing != null;
    final name = TextEditingController(text: existing?.name ?? '');
    final thumb = TextEditingController(text: existing?.thumbnail ?? '');
    final stream = TextEditingController(text: existing?.streamUrl ?? '');
    final clearKey = TextEditingController(text: existing?.drmClearKey ?? '');
    var category = existing?.category ?? kAppChannelCategories.first;
    if (!kAppChannelCategories.contains(category)) {
      category = kAppChannelCategories.first;
    }
    var premium = existing?.premium ?? false;
    var live = existing?.live ?? true;
    var active = existing == null || existing.status == 'active';
    var drm = existing?.effectiveDrm ?? 'none';
    if (!const {'none', 'clearkey', 'widevine'}.contains(drm)) drm = 'none';

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          return AlertDialog(
            backgroundColor: AdminColors.bgSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              isEdit ? 'Hariri chaneli' : 'Ongeza chaneli',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Maelezo ya msingi',
                      style: _channelFormSectionStyle(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: name,
                      decoration: _inputDeco().copyWith(
                        labelText: 'Jina la chaneli',
                        hintText: 'mf. ESPN Ultra HD',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: category,
                      dropdownColor: AdminColors.bgSecondary,
                      decoration: _inputDeco().copyWith(
                        labelText: 'Jamii (kama kwenye app)',
                      ),
                      items: kAppChannelCategories
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(
                                e,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setModal(() => category = v ?? category),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: thumb,
                      decoration: _inputDeco().copyWith(
                        labelText: 'URL ya picha (hiari)',
                        hintText: 'https://…',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: stream,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: _inputDeco().copyWith(
                        labelText: 'URL ya mtangazo',
                        hintText: 'https://…/stream.m3u8',
                        helperText:
                            'HLS, m3u8, au mp4 — inatumika kwenye player ya mtumiaji',
                        prefixIcon: const Icon(
                          Icons.play_circle_outline_rounded,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Upatikanaji', style: _channelFormSectionStyle()),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Chaneli hai',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: active,
                      activeThumbColor: AdminColors.accentSuccess,
                      onChanged: (v) => setModal(() => active = v ?? false),
                    ),
                    const SizedBox(height: 4),
                    Text('Malipo', style: _channelFormSectionStyle()),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Bure'),
                          selected: !premium,
                          onSelected: (_) => setModal(() => premium = false),
                          selectedColor: const Color(0x334CAF50),
                          checkmarkColor: AdminColors.accentSuccess,
                        ),
                        FilterChip(
                          label: const Text('Premium'),
                          selected: premium,
                          onSelected: (_) => setModal(() => premium = true),
                          selectedColor: const Color(0x33F59E0B),
                          checkmarkColor: const Color(0xFFFBBF24),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Mtangazo wa moja kwa moja (Live)',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: live,
                      activeThumbColor: const Color(0xFFEF4444),
                      onChanged: (v) => setModal(() => live = v ?? true),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Ulinzi wa maudhui (DRM)',
                      style: _channelFormSectionStyle(),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: drm,
                      dropdownColor: AdminColors.bgSecondary,
                      decoration: _inputDeco().copyWith(
                        labelText: 'Aina ya DRM',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'none',
                          child: Text('Hakuna DRM'),
                        ),
                        DropdownMenuItem(
                          value: 'clearkey',
                          child: Text('ClearKey'),
                        ),
                        DropdownMenuItem(
                          value: 'widevine',
                          child: Text('Widevine'),
                        ),
                      ],
                      onChanged: (v) => setModal(() => drm = v ?? 'none'),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: drm == 'clearkey'
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: TextField(
                                controller: clearKey,
                                keyboardType: TextInputType.multiline,
                                minLines: 2,
                                maxLines: 4,
                                autocorrect: false,
                                decoration: _inputDeco().copyWith(
                                  labelText: 'ClearKey',
                                  hintText: 'kid_hex:key_hex',
                                  helperText:
                                      'Hex kid:key, kid,key, au JSON {"keys":[{"kid":"…","k":"…"}]}',
                                  helperMaxLines: 2,
                                  prefixIcon: const Icon(
                                    Icons.vpn_key_outlined,
                                    color: Color(0xFF94A3B8),
                                    size: 20,
                                  ),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Ghairi'),
              ),
              FilledButton(
                onPressed: () async {
                  final n = name.text.trim();
                  if (n.isEmpty) {
                    _showToast('Andika jina la chaneli', _ToastType.error);
                    return;
                  }
                  final tUrl = thumb.text.trim();
                  final sUrl = stream.text.trim();
                  final ck = clearKey.text.trim();
                  if (drm == 'clearkey' && ck.isEmpty) {
                    _showToast(
                      'Andika ClearKey kwa chaneli hii',
                      _ToastType.error,
                    );
                    return;
                  }
                  late AdminChannel syncChannel;
                  setState(() {
                    if (isEdit && index != null) {
                      final u = _channels[index];
                      u.name = n;
                      u.category = category;
                      if (tUrl.isNotEmpty) u.thumbnail = tUrl;
                      u.streamUrl = sUrl;
                      u.premium = premium;
                      u.live = live;
                      u.status = active ? 'active' : 'inactive';
                      u.drm = drm;
                      u.drmClearKey = drm == 'clearkey' ? ck : '';
                      syncChannel = u;
                    } else {
                      final created = AdminChannel(
                        id: _nextChannelId(),
                        name: n,
                        category: category,
                        premium: premium,
                        live: live,
                        status: active ? 'active' : 'inactive',
                        thumbnail: tUrl.isEmpty
                            ? 'https://picsum.photos/400/225?random=${DateTime.now().millisecondsSinceEpoch}'
                            : tUrl,
                        streamUrl: sUrl,
                        viewers: 0,
                        rating: '5.0',
                        drm: drm,
                        drmClearKey: drm == 'clearkey' ? ck : '',
                      );
                      _channels.insert(0, created);
                      syncChannel = created;
                    }
                  });
                  if (_hasAdminSession) {
                    final payload = jsonEncode({
                      'name': syncChannel.name,
                      'category': syncChannel.category,
                      'premium': syncChannel.premium,
                      'live': syncChannel.live,
                      'status': syncChannel.status,
                      'thumbnail': syncChannel.thumbnail,
                      'stream_url': syncChannel.streamUrl,
                      'viewers': syncChannel.viewers,
                      'rating': syncChannel.rating,
                      'drm': syncChannel.effectiveDrm,
                      'drm_clear_key': syncChannel.drmClearKey,
                      'sort_order': 0,
                    });
                    try {
                      final res = isEdit
                          ? await http.patch(
                              _adminChannelUri(syncChannel.id),
                              headers: _adminHeaders(),
                              body: payload,
                            )
                          : await http.post(
                              Uri.parse('$_apiBase/api/v1/admin/channels'),
                              headers: _adminHeaders(),
                              body: jsonEncode({
                                'id': syncChannel.id,
                                ...jsonDecode(payload) as Map<String, dynamic>,
                              }),
                            );
                      if (res.statusCode < 200 || res.statusCode >= 300) {
                        throw Exception('channel ${res.statusCode}');
                      }
                      if (mounted) unawaited(_hydrateFromBackend());
                    } catch (_) {
                      _showToast(
                        'Channel local saved, lakini server sync imeshindikana.',
                        _ToastType.warning,
                      );
                    }
                  }
                  if (!mounted) return;
                  Navigator.pop(ctx);
                  _showToast(
                    isEdit ? 'Mabadiliko yamehifadhiwa' : 'Chaneli imeongezwa',
                    _ToastType.success,
                  );
                },
                child: Text(isEdit ? 'Hifadhi' : 'Ongeza'),
              ),
            ],
          );
        },
      ),
    );
  }

  TextStyle _channelFormSectionStyle() => const TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: AdminColors.textSecondary,
  );

  // --- Subscriptions ---
  /// Shell for pages that own a virtualized scroll view (pull-to-refresh still works).
  Widget _ownScrollPage(bool mobile, List<Widget> slivers) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, mobile ? 100 : 24),
          sliver: SliverMainAxisGroup(slivers: slivers),
        ),
      ],
    );
  }

  Widget _emptyListState(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Color(0x146366F1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: const Color(0xFF818CF8), size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AdminColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  bool _subExpired(AdminSubscription s, DateTime now) =>
      !s.endDate.isAfter(now);

  bool _subEndingSoon(AdminSubscription s, DateTime now) =>
      s.endDate.isAfter(now) && s.endDate.difference(now).inHours <= 72;

  List<Widget> _subscriptionSlivers() {
    final now = DateTime.now();
    var active = 0;
    var soon = 0;
    for (final s in _subscriptions) {
      if (!_subExpired(s, now)) active++;
      if (_subEndingSoon(s, now)) soon++;
    }
    final expired = _subscriptions.length - active;
    final q = _subsSearch.text.trim().toLowerCase();
    final list =
        _subscriptions.where((s) {
          final keep = switch (_subsFilter) {
            1 => !_subExpired(s, now),
            2 => _subEndingSoon(s, now),
            3 => _subExpired(s, now),
            _ => true,
          };
          if (!keep) return false;
          if (q.isEmpty) return true;
          return '${s.userName} ${s.plan} ${_pricing[s.plan]?.name ?? ''} ${s.id}'
              .toLowerCase()
              .contains(q);
        }).toList()..sort((a, b) {
          // Active first (soonest to end on top), then the most recently expired.
          final ea = _subExpired(a, now);
          final eb = _subExpired(b, now);
          if (ea != eb) return ea ? 1 : -1;
          return ea
              ? b.endDate.compareTo(a.endDate)
              : a.endDate.compareTo(b.endDate);
        });

    return [
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pageTitleRow(
              title: 'Usajili',
              subtitle: '$active hai · $soon zinaisha ndani ya siku 3',
              action: soon > 0
                  ? _btnOutline(
                      label: 'Reminder',
                      icon: Icons.notifications_active_outlined,
                      onTap: () => _navigate(AdminPageId.notifications),
                    )
                  : null,
            ),
            const SizedBox(height: 14),
            AdminSearchField(
              controller: _subsSearch,
              hint: 'Tafuta jina au kifurushi…',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            AdminFilterChips(
              options: [
                AdminFilterOption('Zote', count: _subscriptions.length),
                AdminFilterOption(
                  'Hai',
                  count: active,
                  color: AdminColors.accentSuccess,
                ),
                AdminFilterOption(
                  'Zinakaribia kuisha',
                  count: soon,
                  color: AdminColors.accentWarning,
                ),
                AdminFilterOption(
                  'Zimeisha',
                  count: expired,
                  color: AdminColors.accentDanger,
                ),
              ],
              selected: _subsFilter,
              onSelected: (i) => setState(() => _subsFilter = i),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
      if (list.isEmpty)
        SliverToBoxAdapter(
          child: _emptyListState(
            Icons.card_membership_rounded,
            q.isEmpty
                ? 'Hakuna usajili katika kundi hili.'
                : 'Hakuna matokeo ya "$q".',
          ),
        )
      else
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 640,
            mainAxisExtent: 84,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _subscriptionTile(list[i], now),
            childCount: list.length,
          ),
        ),
    ];
  }

  Widget _subscriptionTile(AdminSubscription s, DateTime now) {
    final left = s.endDate.difference(now);
    final expired = _subExpired(s, now);
    final soon = _subEndingSoon(s, now);
    final color = expired
        ? AdminColors.accentDanger
        : soon
        ? AdminColors.accentWarning
        : AdminColors.accentSuccess;
    final plan = _pricing[s.plan];
    final totalMinutes = max(1, plan?.duration ?? 30) * 24 * 60;
    final progress = expired
        ? 0.0
        : (left.inMinutes / totalMinutes).clamp(0.02, 1.0).toDouble();
    final leftLabel = expired
        ? 'Imeisha'
        : left.inDays >= 1
        ? 'Siku ${left.inDays}'
        : 'Saa ${max(1, left.inHours)}';
    final meta = _planSlotMeta(s.plan);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      decoration: adminCardDecoration(radius: 16, shadow: false),
      child: Row(
        children: [
          AdminAvatar(s.userName, size: 40, colors: meta.grad),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      fmtTzs(s.price),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Flexible(
                      child: _compactPill(
                        (plan?.name ?? s.plan).toUpperCase(),
                        meta.grad.first,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${expired ? 'Kiliisha' : 'Kinaisha'} ${_fmtDate(s.endDate)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AdminColors.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      leftLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: const Color(0x14FFFFFF),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Pricing ---
  ({String slot, IconData icon, List<Color> grad}) _planSlotMeta(String key) {
    return switch (key) {
      'weekly' => (
        slot: 'Wiki',
        icon: Icons.calendar_view_week_rounded,
        grad: const [Color(0xFF38BDF8), Color(0xFF2563EB)],
      ),
      'gold' => (
        slot: 'Mwezi',
        icon: Icons.workspace_premium_rounded,
        grad: const [Color(0xFFFBBF24), Color(0xFFF97316)],
      ),
      'platinum' => (
        slot: 'Miezi 3',
        icon: Icons.diamond_rounded,
        grad: const [Color(0xFFC084FC), Color(0xFF9333EA)],
      ),
      _ => (
        slot: key,
        icon: Icons.sell_rounded,
        grad: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
      ),
    };
  }

  Widget _pagePricing() {
    const keys = ['weekly', 'gold', 'platinum'];
    final enabled = keys.where((k) => _pricing[k]?.enabled ?? false).length;
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btnOutline(
          label: 'Weka upya',
          icon: Icons.undo_rounded,
          onTap: _resetPricing,
        ),
        const SizedBox(width: 8),
        _btnPrimary(
          label: 'Hifadhi',
          icon: Icons.check_rounded,
          small: true,
          onTap: _savePricing,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final wide = w >= 620;
        final cols = w >= 980 ? 3 : (w >= 620 ? 2 : 1);
        final cardW = (w - (cols - 1) * 12) / cols;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pageTitleRow(
              title: 'Bei za vifurushi',
              subtitle:
                  '$enabled kati ya ${keys.length} vinaonekana kwenye app',
              action: wide ? actions : null,
            ),
            if (!wide) ...[
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final k in keys)
                  SizedBox(width: cardW, child: _pricingPlanEditorCard(k)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _pricingField(
    TextEditingController controller, {
    required String label,
    String? hint,
    String? prefix,
    bool number = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 12,
          color: AdminColors.textSecondary,
        ),
        hintText: hint,
        prefixText: prefix,
        prefixStyle: const TextStyle(
          fontSize: 12.5,
          color: AdminColors.textSecondary,
        ),
        filled: true,
        fillColor: AdminColors.bgPrimary.withValues(alpha: 0.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x14FFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminColors.accentPrimary),
        ),
      ),
    );
  }

  Widget _pricingPlanEditorCard(String key) {
    final p = _pricing[key]!;
    final meta = _planSlotMeta(key);
    _ensurePricingControllers();
    final fields = _pricingFields;
    final nameCtl = fields.name[key]!;
    final priceCtl = fields.price[key]!;
    final daysCtl = fields.days[key]!;
    return AnimatedOpacity(
      opacity: p.enabled ? 1 : 0.6,
      duration: const Duration(milliseconds: 200),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
        decoration: adminCardDecoration(
          radius: 18,
          glow: p.enabled ? meta.grad.first : null,
          shadow: false,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(colors: meta.grad),
                  ),
                  child: Icon(meta.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ListenableBuilder(
                    listenable: daysCtl,
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          meta.slot.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: AdminColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          planPeriodSubtitle(
                            int.tryParse(daysCtl.text.trim()) ?? p.duration,
                          ),
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Tooltip(
                  message: p.enabled
                      ? 'Inaonekana kwenye app'
                      : 'Imefichwa kwenye app',
                  child: Switch(
                    value: p.enabled,
                    activeTrackColor: const Color(0xFF6366F1),
                    thumbColor: const WidgetStatePropertyAll(Colors.white),
                    trackOutlineColor: const WidgetStatePropertyAll(
                      Color(0x26FFFFFF),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => setState(() => p.enabled = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _pricingField(
                    nameCtl,
                    label: 'Jina la kifurushi',
                    hint: 'mf. DHAHABU',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _pricingField(
                          priceCtl,
                          label: 'Bei',
                          prefix: 'TSh ',
                          number: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _pricingField(
                          daysCtl,
                          label: 'Siku',
                          number: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ListenableBuilder(
                    listenable: Listenable.merge([priceCtl, daysCtl]),
                    builder: (context, _) {
                      final price =
                          double.tryParse(
                            priceCtl.text.replaceAll(',', '').trim(),
                          ) ??
                          0;
                      final days = int.tryParse(daysCtl.text.trim()) ?? 0;
                      return Row(
                        children: [
                          const Icon(
                            Icons.insights_rounded,
                            size: 13,
                            color: Color(0xFF818CF8),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              price > 0 && days > 0
                                  ? '≈ ${fmtTzs(price / days)} kwa siku'
                                  : 'Weka bei na siku',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AdminColors.textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            p.enabled ? 'Inaonekana' : 'Imefichwa',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: p.enabled
                                  ? AdminColors.accentSuccess
                                  : AdminColors.textSecondary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _syncPricingDerivedFields() {
    for (final p in _pricing.values) {
      p.originalPrice = p.price;
      p.discount = 0;
    }
  }

  Future<void> _savePricing() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    _applyPricingControllersToPlans();
    final sp = await SharedPreferences.getInstance();
    final map = {
      for (final e in _pricing.entries) e.key: _pricingToJson(e.value),
    };
    await sp.setString('washatvPricing', jsonEncode(map));

    if (!_hasAdminSession) {
      _showToast(
        'Imehifadhiwa local pekee. Ingia tena kwenye skrini ya kwanza.',
        _ToastType.warning,
      );
      return;
    }

    try {
      for (final e in _pricing.entries) {
        final p = e.value;
        final res = await http
            .put(
              Uri.parse('$_apiBase/api/v1/admin/pricing/${e.key}'),
              headers: _adminHeaders(),
              body: jsonEncode({
                'name': p.name,
                'price': p.price,
                'original_price': p.price,
                'discount': 0,
                'duration_days': p.duration,
                'enabled': p.enabled,
                'features': p.features,
                'popular': p.popular,
                'color_key': p.colorKey,
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          final detail = res.body.isNotEmpty
              ? res.body
              : 'HTTP ${res.statusCode}';
          throw Exception('pricing ${e.key}: $detail');
        }
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final row = body['plan'];
        if (row is Map) {
          _applyPricingRowToPlan(e.key, row.cast<String, dynamic>());
        }
      }
      if (!mounted) return;
      setState(() {});
      _syncPricingControllersFromPlans();
      await _persistPricingMapToPrefs();
      if (!mounted) return;
      _showToast(
        'Bei zimehifadhiwa. App ya mtazamaji inasasisha ndani ya sekunde chache.',
        _ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      _showToast(
        'Imeshindikana kuhifadhi bei kwenye server: $e',
        _ToastType.error,
      );
    }
  }

  void _resetPricing() {
    setState(() => _pricing = defaultPricingPlans());
    _syncPricingControllersFromPlans();
    SharedPreferences.getInstance().then((sp) => sp.remove('washatvPricing'));
    _showToast('Imewekwa upya', _ToastType.info);
    if (_hasAdminSession) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_savePricing());
      });
    }
  }

  // --- Payments ---
  bool _paymentPending(AdminPayment p) =>
      p.status != 'completed' && p.status != 'failed';

  Color _paymentColor(String status) => switch (status) {
    'completed' => AdminColors.accentSuccess,
    'failed' => AdminColors.accentDanger,
    _ => AdminColors.accentWarning,
  };

  IconData _paymentIcon(String status) => switch (status) {
    'completed' => Icons.check_circle_rounded,
    'failed' => Icons.cancel_rounded,
    _ => Icons.schedule_rounded,
  };

  String _planLabel(String? key) {
    if (key == null || key.isEmpty) return 'Kifurushi';
    final name = _pricing[key]?.name ?? '';
    return name.isNotEmpty ? name : key.toUpperCase();
  }

  List<Widget> _paymentSlivers() {
    final now = DateTime.now();
    var completed = 0;
    var pending = 0;
    var failed = 0;
    double todayRevenue = 0;
    for (final p in _payments) {
      if (p.status == 'completed') {
        completed++;
        final t = p.createdAt.toLocal();
        if (t.year == now.year && t.month == now.month && t.day == now.day) {
          todayRevenue += p.amount;
        }
      } else if (p.status == 'failed') {
        failed++;
      } else {
        pending++;
      }
    }
    final revenue = _effectiveStats?.revenue ?? todayRevenue;
    final pendingSonic = _payments
        .where((p) => _paymentPending(p) && p.isSonicpesa)
        .length;
    final q = _paySearch.text.trim().toLowerCase();
    final list = _payments.where((p) {
      final keep = switch (_payFilter) {
        1 => p.status == 'completed',
        2 => _paymentPending(p),
        3 => p.status == 'failed',
        _ => true,
      };
      if (!keep) return false;
      if (q.isEmpty) return true;
      return '${p.userName} ${p.transactionId} ${p.id} ${p.phone} ${p.method} ${_planLabel(p.planKey)}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final bulkButton = _bulkVerifying
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0x226366F1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  'Inahakiki…',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          )
        : _btnPrimary(
            label: 'Hakiki zinazosubiri',
            icon: Icons.verified_rounded,
            small: true,
            onTap: () => unawaited(_verifyPendingPayments()),
          );

    return [
      SliverToBoxAdapter(
        child: LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 640;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _pageTitleRow(
                  title: 'Malipo',
                  subtitle:
                      'Malipo ya SonicPesa yanahakikiwa kiotomatiki · ${_payments.length} ya karibuni',
                  action: wide && pendingSonic > 0 ? bulkButton : null,
                ),
                const SizedBox(height: 14),
                _paymentMiniStats(
                  revenue: revenue,
                  completed: completed,
                  pending: pending,
                  failed: failed,
                  width: c.maxWidth,
                ),
                if (!wide && pendingSonic > 0) ...[
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: bulkButton),
                ],
                const SizedBox(height: 14),
                AdminSearchField(
                  controller: _paySearch,
                  hint: 'Tafuta jina, simu au namba ya muamala (sp_…)',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                AdminFilterChips(
                  options: [
                    AdminFilterOption('Zote', count: _payments.length),
                    AdminFilterOption(
                      'Zimekamilika',
                      count: completed,
                      color: AdminColors.accentSuccess,
                    ),
                    AdminFilterOption(
                      'Zinasubiri',
                      count: pending,
                      color: AdminColors.accentWarning,
                    ),
                    AdminFilterOption(
                      'Zimeshindwa',
                      count: failed,
                      color: AdminColors.accentDanger,
                    ),
                  ],
                  selected: _payFilter,
                  onSelected: (i) => setState(() => _payFilter = i),
                ),
                const SizedBox(height: 14),
              ],
            );
          },
        ),
      ),
      if (list.isEmpty)
        SliverToBoxAdapter(
          child: _emptyListState(
            Icons.receipt_long_rounded,
            q.isEmpty
                ? 'Hakuna malipo katika kundi hili.'
                : 'Hakuna matokeo ya "$q".',
          ),
        )
      else
        SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 640,
            mainAxisExtent: 92,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => _paymentTile(list[i], now),
            childCount: list.length,
          ),
        ),
    ];
  }

  Widget _paymentMiniStats({
    required double revenue,
    required int completed,
    required int pending,
    required int failed,
    required double width,
  }) {
    final items = <(String, String, IconData, Color)>[
      (
        'Mapato ya leo',
        fmtTzs(revenue),
        Icons.payments_rounded,
        const Color(0xFFC084FC),
      ),
      (
        'Zimekamilika',
        '$completed',
        Icons.check_circle_rounded,
        AdminColors.accentSuccess,
      ),
      (
        'Zinasubiri',
        '$pending',
        Icons.schedule_rounded,
        AdminColors.accentWarning,
      ),
      (
        'Zimeshindwa',
        '$failed',
        Icons.cancel_rounded,
        AdminColors.accentDanger,
      ),
    ];
    final cols = width >= 640 ? 4 : 2;
    final itemW = (width - (cols - 1) * 10) / cols;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (label, value, icon, color) in items)
          Container(
            width: itemW,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: adminCardDecoration(
              radius: 14,
              glow: color,
              shadow: false,
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AdminColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _paymentTile(AdminPayment p, DateTime now) {
    final color = _paymentColor(p.status);
    final pending = _paymentPending(p);
    return AdminPressable(
      lift: 1,
      pressedScale: 0.99,
      onTap: () => _openPaymentSheet(p),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: adminCardDecoration(radius: 16, shadow: false),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_paymentIcon(p.status), size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        fmtTzs(p.amount),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    p.transactionId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF818CF8),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_planLabel(p.planKey)} · ${p.method} · ${adminTimeAgo(p.createdAt, now)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AdminColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (pending && p.isSonicpesa)
                        _verifyChip(p)
                      else
                        _paymentStateChip(p),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentStateChip(AdminPayment p) {
    final color = _paymentColor(p.status);
    final label = switch (p.status) {
      'completed' => 'Imethibitishwa',
      'failed' => 'Imeshindwa',
      _ => 'Inasubiri',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.status == 'completed') ...[
            Icon(Icons.verified_rounded, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verifyChip(AdminPayment p) {
    final busy = _verifyingRefs.contains(p.transactionId);
    return GestureDetector(
      onTap: busy ? null : () => unawaited(_verifyPayment(p)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: busy ? null : adminBrandGradient,
          color: busy ? const Color(0x226366F1) : null,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: Colors.white,
                ),
              )
            else
              const Icon(
                Icons.verified_outlined,
                size: 12,
                color: Colors.white,
              ),
            const SizedBox(width: 5),
            Text(
              busy ? 'Inahakiki…' : 'Hakiki',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Asks the server to check one order with SonicPesa (same data as sonicpesa.com/verify).
  Future<AdminPayment?> _verifyPayment(AdminPayment p) async {
    final ref = p.transactionId;
    if (_verifyingRefs.contains(ref)) return null;
    if (!_hasAdminSession) {
      _showToast('Ingia tena ili kuhakiki malipo.', _ToastType.warning);
      return null;
    }
    setState(() => _verifyingRefs.add(ref));
    try {
      final res = await http
          .post(
            Uri.parse(
              '$_apiBase/api/v1/admin/transactions/${Uri.encodeComponent(ref)}/verify',
            ),
            headers: _adminHeaders(),
            // Fastify rejects an empty body sent with a JSON Content-Type (400).
            body: '{}',
          )
          .timeout(const Duration(seconds: 25));
      if (res.statusCode == 401 || res.statusCode == 403) {
        await _handleAdminUnauthorized();
        return null;
      }
      final body = await _decodeJsonMapSafe(res.body) ?? <String, dynamic>{};
      if (res.statusCode == 404) {
        _showToast(
          body['status'] == 'not_found'
              ? 'Muamala $ref haupo kwenye kumbukumbu.'
              : 'Seva bado haina uhakiki wa SonicPesa. Sasisha (deploy) backend mpya kwanza.',
          _ToastType.error,
        );
        return null;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _showToast(
          'Uhakiki umeshindikana: ${_s(body['message']).isNotEmpty ? body['message'] : body['error'] ?? 'HTTP ${res.statusCode}'}',
          _ToastType.error,
        );
        return null;
      }
      final tx = body['transaction'];
      final updated = tx is Map
          ? _parsePaymentJson(tx.cast<String, dynamic>())
          : (p
              ..status = _s(body['status'], fallback: p.status)
              ..verifiedAt = DateTime.now()
              ..remoteStatus = _s(body['remote_status']).isEmpty
                  ? p.remoteStatus
                  : _s(body['remote_status']));
      if (!mounted) return updated;
      setState(() {
        final i = _payments.indexWhere((x) => x.id == p.id);
        if (i >= 0) _payments[i] = updated;
      });
      _toastVerifyOutcome(body, updated);
      if (body['newly_granted'] == true) unawaited(_refreshDashboardStats());
      return updated;
    } on TimeoutException {
      _showToast(
        'SonicPesa inachelewa kujibu. Jaribu tena baada ya muda mfupi.',
        _ToastType.warning,
      );
    } catch (e) {
      _showToast('Uhakiki umeshindikana: $e', _ToastType.error);
    } finally {
      if (mounted) setState(() => _verifyingRefs.remove(ref));
    }
    return null;
  }

  void _toastVerifyOutcome(Map<String, dynamic> body, AdminPayment p) {
    final status = _s(body['status']);
    final remote = _s(body['remote_status']);
    final error = _s(body['error']);
    if (remote.isEmpty) {
      _showToast(
        error.isEmpty ? 'SonicPesa haikujibu. Jaribu tena.' : error,
        _ToastType.warning,
      );
      return;
    }
    if (error.isNotEmpty) {
      _showToast(error, _ToastType.warning);
      return;
    }
    if (body['mismatch'] == true) {
      _showToast(
        'Kumbukumbu zinasema imekamilika lakini SonicPesa inasema $remote. Kagua muamala huu.',
        _ToastType.warning,
      );
      return;
    }
    switch (status) {
      case 'completed':
        _showToast(
          body['newly_granted'] == true
              ? 'Malipo yamethibitishwa na premium ya ${p.userName} imewashwa.'
              : 'Imethibitishwa: SonicPesa inasema $remote.',
          _ToastType.success,
        );
      case 'failed':
        _showToast(
          'SonicPesa inasema $remote — malipo hayakufanikiwa.',
          _ToastType.error,
        );
      default:
        _showToast(
          'Bado yanasubiri (SonicPesa: $remote). Mteja hajakamilisha kulipa.',
          _ToastType.info,
        );
    }
  }

  Future<void> _verifyPendingPayments() async {
    if (_bulkVerifying || !_hasAdminSession) return;
    setState(() => _bulkVerifying = true);
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/v1/admin/transactions/verify-pending'),
            headers: _adminHeaders(),
            body: '{}',
          )
          .timeout(const Duration(seconds: 90));
      if (res.statusCode == 401 || res.statusCode == 403) {
        await _handleAdminUnauthorized();
        return;
      }
      final body = await _decodeJsonMapSafe(res.body) ?? <String, dynamic>{};
      if (res.statusCode == 404) {
        _showToast(
          'Seva bado haina uhakiki wa SonicPesa. Sasisha (deploy) backend mpya kwanza.',
          _ToastType.error,
        );
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _showToast(
          _s(
            body['message'] ?? body['error'],
            fallback: 'Uhakiki umeshindikana (${res.statusCode}).',
          ),
          res.statusCode == 409 ? _ToastType.info : _ToastType.error,
        );
        return;
      }
      final checked = _toInt(body['checked']);
      final completed = _toInt(body['completed']);
      final failed = _toInt(body['failed']);
      final still = _toInt(body['still_pending']);
      final unreachable = _toInt(body['unreachable']);
      if (checked == 0) {
        _showToast('Hakuna malipo yanayosubiri ya kuhakiki.', _ToastType.info);
      } else {
        _showToast(
          'Yamekaguliwa $checked: $completed yamekamilika, $failed yameshindwa, $still bado yanasubiri'
          '${unreachable > 0 ? ' ($unreachable SonicPesa haikujibu)' : ''}.',
          completed > 0 ? _ToastType.success : _ToastType.info,
        );
      }
      await _reloadPayments();
      if (completed > 0) unawaited(_refreshDashboardStats());
    } on TimeoutException {
      _showToast(
        'Uhakiki unaendelea kwenye seva. Pakia upya baada ya dakika moja.',
        _ToastType.warning,
      );
    } catch (e) {
      _showToast('Uhakiki umeshindikana: $e', _ToastType.error);
    } finally {
      if (mounted) setState(() => _bulkVerifying = false);
    }
  }

  void _openPaymentSheet(AdminPayment payment) {
    var current = payment;
    var busy = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AdminColors.bgSecondary,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final p = current;
          final color = _paymentColor(p.status);
          Widget row(String label, String value, {bool copy = false}) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value.isEmpty ? '—' : value,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (copy && value.isNotEmpty)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: value));
                        _showToast('Imenakiliwa', _ToastType.success);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 15,
                          color: Color(0xFF818CF8),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _paymentIcon(p.status),
                          color: color,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fmtTzs(p.amount),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              _swStatus(p.status),
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Color(0x14FFFFFF), height: 1),
                  const SizedBox(height: 8),
                  row('Mtumiaji', p.userName),
                  row('Kifurushi', _planLabel(p.planKey)),
                  row('Njia', p.method),
                  row('Simu', p.phone),
                  row('Namba ya SonicPesa', p.transactionId, copy: true),
                  if (p.id != p.transactionId) row('Muamala', p.id, copy: true),
                  row('Tarehe', _formatLogDateTime(p.createdAt.toLocal())),
                  row(
                    'Uhakiki wa mwisho',
                    p.verifiedAt == null
                        ? 'Bado'
                        : '${adminTimeAgo(p.verifiedAt!)}${p.remoteStatus == null ? '' : ' · ${p.remoteStatus}'}',
                  ),
                  const SizedBox(height: 16),
                  if (p.isSonicpesa)
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () async {
                              setLocal(() => busy = true);
                              final updated = await _verifyPayment(p);
                              if (!ctx.mounted) return;
                              setLocal(() {
                                busy = false;
                                if (updated != null) current = updated;
                              });
                            },
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminColors.accentPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.verified_rounded, size: 18),
                      label: Text(
                        busy
                            ? 'Inahakiki na SonicPesa…'
                            : 'Hakiki na SonicPesa',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    p.isSonicpesa
                        ? 'Uhakiki unauliza SonicPesa moja kwa moja (taarifa sawa na sonicpesa.com/verify). '
                              'Yakifanikiwa, premium ya mtumiaji huwashwa papo hapo.'
                        : 'Muamala huu haukulipwa kupitia SonicPesa.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: AdminColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- Notifications & subscription reminders ---

  List<AdminNotification> _parseNotificationsJson(List raw) {
    return raw.whereType<Map>().map((rawItem) {
      final j = rawItem.cast<String, dynamic>();
      return AdminNotification(
        id: _s(j['id']),
        title: _s(j['title']),
        message: _s(j['message']),
        type: _s(j['type'], fallback: 'info'),
        read: j['read'] as bool? ?? false,
        createdAt: _dt(j['created_at']) ?? DateTime.now(),
        target: _s(j['target'], fallback: 'all'),
        delivery: _s(j['delivery'], fallback: 'unknown'),
        sentCount: _toInt(j['sent_count']),
        failedCount: _toInt(j['failed_count']),
        error: _s(j['error']).isEmpty ? null : _s(j['error']),
      );
    }).toList();
  }

  List<ReminderUser> _parseReminderUsers(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final list = (jsonDecode(res.body) as Map)['users'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((raw) {
      final j = raw.cast<String, dynamic>();
      return ReminderUser(
        id: _s(j['id']),
        name: _s(j['name']),
        phone: _s(j['phone']),
        deviceId: _s(j['device_id']),
        endsAt: _dt(j['ends_at']),
        remindedAt: _dt(j['reminded_at']),
      );
    }).toList();
  }

  /// Reminder counts + the users behind them (expiring within N days / already expired).
  Future<void> _loadReminderData() async {
    if (!_hasAdminSession || _remindersLoading) return;
    setState(() {
      _remindersLoading = true;
      _remindersError = null;
    });
    try {
      Uri usersUri(String audience) => Uri.parse(
        '$_apiBase/api/v1/admin/reminders/users',
      ).replace(queryParameters: {'audience': audience, 'limit': '200'});
      final results = await Future.wait([
        http.get(
          Uri.parse('$_apiBase/api/v1/admin/reminders/summary'),
          headers: _adminHeaders(),
        ),
        http.get(usersUri('expiring'), headers: _adminHeaders()),
        http.get(usersUri('expired'), headers: _adminHeaders()),
      ]).timeout(const Duration(seconds: 20));
      if (results.any((r) => r.statusCode == 401 || r.statusCode == 403)) {
        await _handleAdminUnauthorized();
        return;
      }
      final summaryRes = results[0];
      if (summaryRes.statusCode == 404) {
        throw Exception(
          'Seva bado haina reminder. Sasisha (deploy) backend mpya kwanza.',
        );
      }
      if (summaryRes.statusCode < 200 || summaryRes.statusCode >= 300) {
        throw Exception('Seva imejibu ${summaryRes.statusCode}.');
      }
      final s = (jsonDecode(summaryRes.body) as Map).cast<String, dynamic>();
      final templates =
          (s['templates'] as Map?)?.cast<String, dynamic>() ?? const {};
      final exp =
          (templates['expiring'] as Map?)?.cast<String, dynamic>() ?? const {};
      final gone =
          (templates['expired'] as Map?)?.cast<String, dynamic>() ?? const {};
      final summary = ReminderSummary(
        days: _toInt(s['days']) > 0 ? _toInt(s['days']) : 3,
        expiring: _toInt(s['expiring']),
        expiringUnsent: _toInt(s['expiring_unsent']),
        expired: _toInt(s['expired']),
        expiredUnsent: _toInt(s['expired_unsent']),
        pushConfigured: s['push_configured'] != false,
        autoReminders: s['auto_reminders'] != false,
        expiringTitle: _s(exp['title']),
        expiringBody: _s(exp['body']),
        expiredTitle: _s(gone['title']),
        expiredBody: _s(gone['body']),
      );
      if (!mounted) return;
      setState(() {
        _reminderSummary = summary;
        _expiringUsers = _parseReminderUsers(results[1]);
        _expiredUsers = _parseReminderUsers(results[2]);
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(
        () => _remindersError = msg.contains('Seva')
            ? msg
            : 'Imeshindwa kupakia reminder. Angalia mtandao kisha ujaribu tena.',
      );
    } finally {
      if (mounted) setState(() => _remindersLoading = false);
    }
  }

  Future<void> _reloadNotifications() async {
    if (!_hasAdminSession) return;
    try {
      final res = await http
          .get(
            Uri.parse('$_apiBase/api/v1/admin/notifications'),
            headers: _adminHeaders(),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 401 || res.statusCode == 403) {
        await _handleAdminUnauthorized();
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final raw = (jsonDecode(res.body) as Map)['notifications'];
      if (raw is! List || !mounted) return;
      setState(() => _notifications = _parseNotificationsJson(raw));
    } catch (_) {}
  }

  String? _readApiError(String body) {
    try {
      final err = (jsonDecode(body) as Map)['error'];
      if (err is String && err.trim().isNotEmpty) return err.trim();
    } catch (_) {}
    return null;
  }

  /// "leo" / "kesho" / "baada ya siku N" / "jana" / "siku N zilizopita".
  String _swDayDistance(DateTime d) {
    final now = DateTime.now();
    final days = DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days == 0) return 'leo';
    if (days == 1) return 'kesho';
    if (days > 1) return 'baada ya siku $days';
    if (days == -1) return 'jana';
    return 'siku ${-days} zilizopita';
  }

  String _notificationTargetLabel(String target) {
    if (target == 'all') return 'Wote';
    if (target == 'premium') return 'Premium';
    if (target == 'free') return 'Bure';
    if (target.startsWith('user:')) {
      final id = target.substring(5);
      return 'Mtumiaji: ${id.length > 14 ? '${id.substring(0, 14)}…' : id}';
    }
    if (target.startsWith('reminder:')) {
      final parts = target.split(':');
      final who = parts.length > 1 && parts[1] == 'expired'
          ? 'walioisha'
          : 'wanaokaribia kuisha';
      final how = parts.length > 2 && parts[2] == 'auto'
          ? 'otomatiki'
          : 'admin';
      return 'Reminder · $who · $how';
    }
    return target;
  }

  (String, Color) _deliveryBadge(String delivery) {
    return switch (delivery) {
      'sent' => ('Imetumwa', AdminColors.accentSuccess),
      'partial' => ('Sehemu imefika', const Color(0xFFF59E0B)),
      'bridge' => ('Kupitia Supasoka', const Color(0xFF3B82F6)),
      'not_configured' => ('FCM haijasanidiwa', const Color(0xFFF59E0B)),
      'failed' => ('Imeshindwa', AdminColors.accentDanger),
      _ => ('Haijulikani', const Color(0xFF6B7280)),
    };
  }

  Future<void> _deleteNotification(AdminNotification n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.bgSecondary,
        title: const Text('Futa kwenye historia?'),
        content: const Text(
          'Hii inafuta rekodi hapa tu — arifa iliyokwisha tumwa haitaondoka kwenye simu za watumiaji.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ghairi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Futa'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final res = await http
          .delete(
            Uri.parse(
              '$_apiBase/api/v1/admin/notifications/${Uri.encodeComponent(n.id)}',
            ),
            headers: _adminHeadersForDelete(),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 401 || res.statusCode == 403) {
        await _handleAdminUnauthorized();
        return;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('${res.statusCode}');
      }
      if (!mounted) return;
      setState(() => _notifications.removeWhere((x) => x.id == n.id));
      _showToast('Imefutwa kwenye historia', _ToastType.success);
    } catch (e) {
      if (mounted) _showToast('Imeshindwa kufuta: $e', _ToastType.error);
    }
  }

  /// Compose + send a subscription reminder to everyone in [audience] (`expiring` / `expired`).
  Future<void> _openReminderComposer(String audience) async {
    final s = _reminderSummary ?? const ReminderSummary();
    final expiring = audience == 'expiring';
    if (!s.pushConfigured) {
      _showToast(
        'FCM haijasanidiwa kwenye seva — reminder haziwezi kutumwa.',
        _ToastType.error,
      );
      return;
    }
    final title = TextEditingController(
      text: expiring ? s.expiringTitle : s.expiredTitle,
    );
    final body = TextEditingController(
      text: expiring ? s.expiringBody : s.expiredBody,
    );
    // Expiring: skip people already reminded for this subscription. Expired: reach everyone by default.
    var onlyUnsent = expiring;
    var sending = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final total = expiring ? s.expiring : s.expired;
          final unsent = expiring ? s.expiringUnsent : s.expiredUnsent;
          final recipients = onlyUnsent ? unsent : total;
          return AlertDialog(
            backgroundColor: AdminColors.bgSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              expiring ? 'Reminder: vinakaribia kuisha' : 'Reminder: vimeisha',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expiring
                          ? 'Watumiaji ambao kifurushi chao kinaisha ndani ya siku ${s.days}.'
                          : 'Watumiaji ambao kifurushi chao kimeshaisha.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: title,
                      maxLength: 100,
                      decoration: _inputDeco().copyWith(labelText: 'Kichwa'),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: body,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: _inputDeco().copyWith(labelText: 'Ujumbe'),
                    ),
                    Text(
                      expiring
                          ? '{jina} = jina la mtumiaji · {muda} = "leo", "kesho" au "baada ya siku 3"'
                          : '{jina} = jina la mtumiaji',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: onlyUnsent,
                      onChanged: sending
                          ? null
                          : (v) => setLocal(() => onlyUnsent = v ?? false),
                      title: const Text(
                        'Ruka waliokwisha pata reminder',
                        style: TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        'Wote: $total · Hawajakumbushwa: $unsent',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AdminColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0x226366F1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        recipients == 0
                            ? 'Hakuna mtumiaji wa kutumiwa reminder hii.'
                            : 'Watumiaji $recipients watapokea reminder hii.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(ctx),
                child: const Text('Ghairi'),
              ),
              FilledButton.icon(
                onPressed: sending || recipients == 0
                    ? null
                    : () async {
                        if (title.text.trim().isEmpty ||
                            body.text.trim().isEmpty) {
                          _showToast(
                            'Andika kichwa na ujumbe',
                            _ToastType.error,
                          );
                          return;
                        }
                        setLocal(() => sending = true);
                        final done = await _sendReminders(
                          audience: audience,
                          title: title.text.trim(),
                          body: body.text.trim(),
                          onlyUnsent: onlyUnsent,
                        );
                        if (!ctx.mounted) return;
                        if (done) {
                          Navigator.pop(ctx);
                        } else {
                          setLocal(() => sending = false);
                        }
                      },
                icon: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(sending ? 'Inatuma…' : 'Tuma reminder'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _sendReminders({
    required String audience,
    required String title,
    required String body,
    required bool onlyUnsent,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/v1/admin/reminders/send'),
            headers: _adminHeaders(),
            body: jsonEncode({
              'audience': audience,
              'title': title,
              'body': body,
              'only_unsent': onlyUnsent,
            }),
          )
          // Large audiences are sent in batches of 500 — give the server time.
          .timeout(const Duration(seconds: 120));
      if (res.statusCode == 401 || res.statusCode == 403) {
        await _handleAdminUnauthorized();
        return false;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _showToast(
          _readApiError(res.body) ??
              'Kutuma kumeshindikana (${res.statusCode}).',
          _ToastType.error,
        );
        return false;
      }
      final out = (jsonDecode(res.body) as Map).cast<String, dynamic>();
      final sent = _toInt(out['sent']);
      final failed = _toInt(out['failed']);
      final total = _toInt(out['total']);
      if (total == 0) {
        _showToast('Hakuna mtumiaji aliyestahili kutumiwa.', _ToastType.info);
      } else if (sent == 0) {
        _showToast(
          'Hakuna reminder iliyofika (zimeshindwa $failed). Huenda watumiaji hawajawasha arifa.',
          _ToastType.error,
        );
      } else {
        _showToast(
          failed == 0
              ? 'Reminder $sent zimetumwa!'
              : 'Zimetumwa $sent, zimeshindwa $failed (jumla $total).',
          failed == 0 ? _ToastType.success : _ToastType.warning,
        );
      }
      unawaited(_loadReminderData());
      unawaited(_reloadNotifications());
      return true;
    } on TimeoutException {
      _showToast(
        'Seva inachukua muda mrefu. Angalia historia baada ya dakika moja kabla ya kutuma tena.',
        _ToastType.warning,
      );
      unawaited(_reloadNotifications());
      return true;
    } catch (e) {
      _showToast('Hitilafu ya mtandao: $e', _ToastType.error);
      return false;
    }
  }

  Widget _reminderNotice(
    String text, {
    Color color = const Color(0xFFF59E0B),
    IconData icon = Icons.warning_amber_rounded,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color.lerp(color, Colors.white, 0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reminderCard({
    required String audience,
    required String title,
    required String subtitle,
    required int count,
    required int unsent,
    required List<ReminderUser> users,
    required Color color,
    required IconData icon,
  }) {
    final loading = _remindersLoading && _reminderSummary == null;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: adminCardDecoration(radius: 18, glow: color, shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                loading ? '…' : '$count',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  unsent == 0
                      ? (count == 0
                            ? 'Hakuna wa kukumbusha'
                            : 'Wote wamepata reminder')
                      : '$unsent hawajapata reminder',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AdminColors.textSecondary,
                  ),
                ),
              ),
              if (users.isNotEmpty)
                TextButton(
                  onPressed: () => _openReminderUsersSheet(
                    title: title,
                    users: users,
                    total: count,
                    expiring: audience == 'expiring',
                    color: color,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: AdminColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text(
                    'Ona orodha',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: count == 0
                    ? null
                    : () => unawaited(_openReminderComposer(audience)),
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.send_rounded, size: 14),
                label: const Text(
                  'Tuma',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openReminderUsersSheet({
    required String title,
    required List<ReminderUser> users,
    required int total,
    required bool expiring,
    required Color color,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AdminColors.bgSecondary,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, scroll) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0x33FFFFFF),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    users.length < total
                        ? '${users.length} kati ya $total'
                        : '$total',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                itemExtent: 64,
                itemCount: users.length,
                itemBuilder: (ctx, i) {
                  final u = users[i];
                  final ends = u.endsAt;
                  final name = u.name.isEmpty || u.name == 'Viewer'
                      ? 'Mtumiaji'
                      : u.name;
                  final phone = u.phone.isEmpty || u.phone == 'N/A'
                      ? ''
                      : ' · ${u.phone}';
                  final reminded = u.remindedAt != null;
                  return Row(
                    children: [
                      AdminAvatar(name, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$name$phone',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (ends != null)
                              Text(
                                '${expiring ? 'Kinaisha' : 'Kiliisha'} ${_swDayDistance(ends)} · ${_fmtAccessDate(ends)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AdminColors.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _compactPill(
                        reminded
                            ? 'Amepata ${_swDayDistance(u.remindedAt!)}'
                            : 'Hajapata',
                        reminded
                            ? AdminColors.accentSuccess
                            : const Color(0xFF94A3B8),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isReminderNotification(AdminNotification n) =>
      n.type == 'reminder' || n.target.startsWith('reminder:');

  Widget _notificationHistoryTile(AdminNotification n) {
    final (label, color) = _deliveryBadge(n.delivery);
    final isReminder = _isReminderNotification(n);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 2, 10),
      decoration: adminCardDecoration(radius: 14, shadow: false),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              isReminder ? Icons.alarm_rounded : Icons.campaign_rounded,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      adminTimeAgo(n.createdAt),
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  n.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AdminColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _compactPill(label, color),
                    _compactPill(
                      _notificationTargetLabel(n.target),
                      const Color(0xFF818CF8),
                    ),
                    if (n.sentCount + n.failedCount > 0)
                      Text(
                        'imefika ${n.sentCount}${n.failedCount > 0 ? ' · imeshindwa ${n.failedCount}' : ''}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AdminColors.textSecondary,
                        ),
                      ),
                  ],
                ),
                if (n.error != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    n.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFF87171),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Futa kwenye historia',
            visualDensity: VisualDensity.compact,
            onPressed: () => unawaited(_deleteNotification(n)),
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 17,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageNotifications() {
    final s = _reminderSummary;
    final days = s?.days ?? 3;
    final reminders = _notifications.where(_isReminderNotification).length;
    final history = switch (_historyFilter) {
      1 => _notifications.where((n) => !_isReminderNotification(n)).toList(),
      2 => _notifications.where(_isReminderNotification).toList(),
      _ => _notifications,
    };
    final shown = history.take(_historyShown).toList();
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Pakia upya',
          onPressed: _remindersLoading
              ? null
              : () {
                  unawaited(_loadReminderData());
                  unawaited(_reloadNotifications());
                },
          icon: _remindersLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(
                  Icons.refresh_rounded,
                  size: 20,
                  color: AdminColors.textSecondary,
                ),
        ),
        const SizedBox(width: 4),
        _btnPrimary(
          label: 'Tuma arifa',
          icon: Icons.send_rounded,
          small: true,
          onTap: _modalSendNotification,
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pageTitleRow(
              title: 'Arifa na Reminder',
              subtitle: 'Tuma arifa na uwakumbushe watumiaji kulipia vifurushi',
              action: wide ? actions : null,
            ),
            if (!wide) ...[
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
            const SizedBox(height: 14),
            if (_remindersError != null)
              _reminderNotice(
                _remindersError!,
                color: AdminColors.accentDanger,
                icon: Icons.error_outline_rounded,
              ),
            if (s != null && !s.pushConfigured)
              _reminderNotice(
                'FCM haijasanidiwa kwenye seva, kwa hiyo arifa hazitafika. '
                'Weka FCM_SERVICE_ACCOUNT_JSON kwenye Railway.',
              ),
            if (s != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (s.pushConfigured)
                    _statusChip(
                      Icons.check_circle_rounded,
                      'Arifa ziko tayari',
                      AdminColors.accentSuccess,
                    ),
                  _statusChip(
                    s.autoReminders
                        ? Icons.auto_mode_rounded
                        : Icons.pause_circle_outline_rounded,
                    s.autoReminders
                        ? 'Reminder otomatiki: zimewashwa'
                        : 'Reminder otomatiki: zimezimwa',
                    s.autoReminders
                        ? AdminColors.accentPrimary
                        : const Color(0xFF94A3B8),
                  ),
                  if (s.autoReminders) ...[
                    _statusChip(
                      Icons.schedule_rounded,
                      'Saa 2 asubuhi – saa 2 usiku',
                      const Color(0xFF38BDF8),
                    ),
                    _statusChip(
                      Icons.hourglass_bottom_rounded,
                      'Siku $days kabla ya kuisha',
                      AdminColors.accentWarning,
                    ),
                    _statusChip(
                      Icons.event_busy_rounded,
                      'Walioisha ndani ya siku 2',
                      AdminColors.accentDanger,
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 14),
            Builder(
              builder: (context) {
                final a = _reminderCard(
                  audience: 'expiring',
                  title: 'Vinakaribia kuisha',
                  subtitle: 'Vinaisha ndani ya siku $days',
                  count: s?.expiring ?? 0,
                  unsent: s?.expiringUnsent ?? 0,
                  users: _expiringUsers,
                  color: const Color(0xFFF59E0B),
                  icon: Icons.hourglass_bottom_rounded,
                );
                final b = _reminderCard(
                  audience: 'expired',
                  title: 'Vimeisha',
                  subtitle: 'Vifurushi vilivyokwisha',
                  count: s?.expired ?? 0,
                  unsent: s?.expiredUnsent ?? 0,
                  users: _expiredUsers,
                  color: AdminColors.accentDanger,
                  icon: Icons.event_busy_rounded,
                );
                if (c.maxWidth < 760) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [a, const SizedBox(height: 10), b],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: 12),
                    Expanded(child: b),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            const Text(
              'Historia',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            AdminFilterChips(
              options: [
                AdminFilterOption('Zote', count: _notifications.length),
                AdminFilterOption(
                  'Arifa',
                  count: _notifications.length - reminders,
                ),
                AdminFilterOption(
                  'Reminder',
                  count: reminders,
                  color: AdminColors.accentWarning,
                ),
              ],
              selected: _historyFilter,
              onSelected: (i) => setState(() {
                _historyFilter = i;
                _historyShown = 30;
              }),
            ),
            const SizedBox(height: 12),
            if (history.isEmpty)
              _emptyListState(
                Icons.notifications_none_rounded,
                'Hakuna kilichotumwa bado.',
              ),
            ...shown.map(_notificationHistoryTile),
            if (history.length > shown.length)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _historyShown += 30),
                  child: Text(
                    'Onyesha zaidi (${history.length - shown.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // --- Analytics ---
  Widget _pageAnalytics() {
    final stats = _effectiveStats;
    final loading = stats == null;
    final live = stats?.live ?? const AdminLiveStats();
    final total = stats?.totalUsers ?? 0;
    final premium = stats?.premiumUsers ?? 0;
    final updated = _statsFetchedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  const Flexible(child: AdminPageHeading('Takwimu')),
                  const SizedBox(width: 10),
                  if (_hasAdminSession && !_statsRefreshFailed && !loading)
                    const AdminLiveBadge(),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Sasisha sasa',
              onPressed: () => unawaited(_refreshDashboardStats()),
              icon: const Icon(
                Icons.refresh_rounded,
                size: 20,
                color: AdminColors.textSecondary,
              ),
            ),
          ],
        ),
        Text(
          _statsRefreshFailed
              ? 'Imeshindwa kusasisha — inajaribu tena…'
              : updated == null
              ? 'Inapakia takwimu…'
              : 'Inajisasisha kila sekunde 10 · mara ya mwisho ${adminTimeAgo(updated)}',
          style: TextStyle(
            fontSize: 12,
            color: _statsRefreshFailed
                ? const Color(0xFFF87171)
                : AdminColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth < 640 ? 2 : (c.maxWidth < 1100 ? 3 : 4);
            final cards = <Widget>[
              _statCard(
                label: 'Online sasa (dak 5)',
                value: loading ? null : live.onlineNow,
                icon: Icons.wifi_tethering_rounded,
                iconBg: const Color(0x2210B981),
                iconColor: const Color(0xFF34D399),
              ),
              _statCard(
                label: 'Waliotumia leo',
                value: loading ? null : live.activeToday,
                icon: Icons.today_rounded,
                iconBg: const Color(0x223B82F6),
                iconColor: const Color(0xFF60A5FA),
              ),
              _statCard(
                label: 'Wapya leo',
                value: loading ? null : live.newUsersToday,
                icon: Icons.person_add_alt_1_rounded,
                iconBg: const Color(0x226366F1),
                iconColor: const Color(0xFF818CF8),
                onTap: () => _navigate(AdminPageId.users),
              ),
              _statCard(
                label: 'Mapato ya leo',
                value: stats?.revenue,
                format: fmtTzs,
                icon: Icons.payments_rounded,
                iconBg: const Color(0x229333EA),
                iconColor: const Color(0xFFC084FC),
              ),
              _statCard(
                label: 'Mapato siku 7',
                value: loading ? null : live.revenue7d,
                format: fmtTzs,
                icon: Icons.date_range_rounded,
                iconBg: const Color(0x229333EA),
                iconColor: const Color(0xFFC084FC),
              ),
              _statCard(
                label: 'Mapato siku 30',
                value: loading ? null : live.revenue30d,
                format: fmtTzs,
                icon: Icons.calendar_month_rounded,
                iconBg: const Color(0x229333EA),
                iconColor: const Color(0xFFC084FC),
              ),
              _statCard(
                label: 'Malipo yanasubiri',
                value: loading ? null : live.pendingPayments,
                icon: Icons.hourglass_top_rounded,
                iconBg: const Color(0x22F59E0B),
                iconColor: const Color(0xFFFBBF24),
                onTap: () {
                  _payFilter = 2;
                  _navigate(AdminPageId.payments);
                },
              ),
              _statCard(
                label: total > 0
                    ? 'Premium hai · ${(premium * 100 / total).toStringAsFixed(1)}%'
                    : 'Premium hai',
                value: loading ? null : premium,
                icon: Icons.workspace_premium_rounded,
                iconBg: const Color(0x22F59E0B),
                iconColor: const Color(0xFFFBBF24),
                onTap: () => _navigate(AdminPageId.subscriptions),
              ),
            ];
            return GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 124,
              ),
              children: [
                for (var i = 0; i < cards.length; i++)
                  FadeSlideIn(index: i, child: cards[i]),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _analyticsTrendCard(stats),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final a = _analyticsPlanCard(stats);
            final b = _analyticsAudienceCard(stats);
            if (c.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [a, const SizedBox(height: 16), b],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: a),
                  const SizedBox(width: 16),
                  Expanded(child: b),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _analyticsRecentPayments(stats),
      ],
    );
  }

  Widget _analyticsCardTitle(String title, {Widget? trailing}) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            gradient: adminBrandGradient,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _analyticsTrendCard(AdminDashboardStats? stats) {
    final days = stats?.days14 ?? const <AdminDayStat>[];
    const metrics = ['Usajili', 'Mauzo', 'Mapato'];
    const colors = [Color(0xFF818CF8), Color(0xFF34D399), Color(0xFFC084FC)];
    final m = _analyticsMetric;
    final color = colors[m];
    final values = [
      for (final d in days)
        switch (m) {
          0 => d.registrations.toDouble(),
          1 => d.purchases.toDouble(),
          _ => d.revenue,
        },
    ];
    final total = values.fold<double>(0, (a, b) => a + b);
    final peak = values.fold<double>(0, max);
    String fmt(num v) => m == 2 ? fmtTzs(v) : '${v.round()}';
    final step = peak <= 0 ? 1.0 : max(1.0, (peak / 4).ceilToDouble());
    final maxY = peak <= 0 ? 4.0 : (peak / step).ceil() * step + step * 0.25;
    const swDays = ['Jtt', 'Jnn', 'Jtn', 'Alh', 'Iju', 'Jms', 'Jpl'];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _analyticsCardTitle(
            'Siku 14 zilizopita',
            trailing: Text(
              'Jumla: ${fmt(total)}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 12),
          AdminFilterChips(
            options: [
              for (var i = 0; i < metrics.length; i++)
                AdminFilterOption(metrics[i], color: colors[i]),
            ],
            selected: m,
            onSelected: (i) => setState(() => _analyticsMetric = i),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 220,
            child: days.isEmpty
                ? Center(
                    child: Text(
                      stats == null
                          ? 'Inapakia…'
                          : 'Sasisha (deploy) backend mpya ili kuona takwimu za kila siku.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminColors.textSecondary,
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, c) {
                      final barW = (c.maxWidth / days.length * 0.5).clamp(
                        6.0,
                        22.0,
                      );
                      return BarChart(
                        BarChartData(
                          maxY: maxY,
                          minY: 0,
                          alignment: BarChartAlignment.spaceAround,
                          borderData: FlBorderData(show: false),
                          gridData: FlGridData(
                            drawVerticalLine: false,
                            horizontalInterval: step,
                            getDrawingHorizontalLine: (_) => const FlLine(
                              color: Color(0x12FFFFFF),
                              strokeWidth: 1,
                            ),
                          ),
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (_) => AdminColors.bgSecondary,
                              tooltipRoundedRadius: 10,
                              getTooltipItem: (group, gi, rod, ri) {
                                final d = days[group.x].day;
                                return BarTooltipItem(
                                  '${swDays[d.weekday - 1]} ${d.day}/${d.month}\n',
                                  const TextStyle(
                                    fontSize: 11,
                                    color: AdminColors.textSecondary,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: fmt(rod.toY),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: color,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(),
                            rightTitles: const AxisTitles(),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: m == 2 ? 40 : 30,
                                interval: step,
                                getTitlesWidget: (v, meta) {
                                  final r = v / step;
                                  if ((r - r.round()).abs() > 0.01) {
                                    return const SizedBox.shrink();
                                  }
                                  return Text(
                                    m == 2
                                        ? fmtTzsAxis(v)
                                        : v.toInt().toString(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF6B7280),
                                    ),
                                  );
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 24,
                                getTitlesWidget: (v, meta) {
                                  final i = v.toInt();
                                  if (i < 0 || i >= days.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final last = i == days.length - 1;
                                  if (c.maxWidth < 480 && i.isOdd && !last) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      last ? 'Leo' : '${days[i].day.day}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: last
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                        color: last
                                            ? color
                                            : const Color(0xFF6B7280),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: [
                            for (var i = 0; i < values.length; i++)
                              BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: values[i],
                                    width: barW,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(5),
                                    ),
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        color.withValues(alpha: 0.35),
                                        color,
                                      ],
                                    ),
                                    backDrawRodData: BackgroundBarChartRodData(
                                      show: true,
                                      toY: maxY,
                                      color: const Color(0x08FFFFFF),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        duration: const Duration(milliseconds: 350),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _analyticsPlanCard(AdminDashboardStats? stats) {
    final items = <(String, int, Color)>[
      ('Wiki', stats?.planWeekly ?? 0, const Color(0xFF3B82F6)),
      ('Mwezi', stats?.planGold ?? 0, const Color(0xFFF59E0B)),
      ('Miezi 3', stats?.planPlatinum ?? 0, const Color(0xFF8B5CF6)),
      if ((stats?.planOther ?? 0) > 0)
        ('Nyingine', stats!.planOther, const Color(0xFF6B7280)),
    ];
    final total = items.fold<int>(0, (a, e) => a + e.$2);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _analyticsCardTitle('Vifurushi vilivyonunuliwa'),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: total > 0 ? 3 : 0,
                        centerSpaceRadius: 44,
                        startDegreeOffset: -90,
                        sections: total == 0
                            ? [
                                PieChartSectionData(
                                  value: 1,
                                  color: const Color(0x14FFFFFF),
                                  radius: 16,
                                  showTitle: false,
                                ),
                              ]
                            : [
                                for (final (_, count, color) in items)
                                  if (count > 0)
                                    PieChartSectionData(
                                      value: count.toDouble(),
                                      color: color,
                                      radius: 16,
                                      showTitle: false,
                                    ),
                              ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$total',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'mauzo',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AdminColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    for (final (label, count, color) in items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: _analyticsShareRow(
                          label: label,
                          value: '$count',
                          share: total == 0 ? 0 : count / total,
                          color: color,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _analyticsShareRow({
    required String label,
    required String value,
    required double share,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(
              width: 44,
              child: Text(
                '${(share * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 11,
                  color: AdminColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: share.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 4,
              backgroundColor: const Color(0x12FFFFFF),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }

  Widget _analyticsAudienceCard(AdminDashboardStats? stats) {
    final total = stats?.totalUsers ?? 0;
    final live = stats?.live ?? const AdminLiveStats();
    double share(int v) => total <= 0 ? 0 : v / total;
    final rows = <(String, int, Color)>[
      ('Premium hai', stats?.premiumUsers ?? 0, const Color(0xFFFBBF24)),
      ('Bure', stats?.freeUsers ?? 0, const Color(0xFF94A3B8)),
      ('Walioingia siku 7', live.active7d, const Color(0xFF60A5FA)),
      ('Waliotumia leo', live.activeToday, const Color(0xFF34D399)),
    ];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _analyticsCardTitle(
            'Watumiaji',
            trailing: Text(
              '$total jumla',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF818CF8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final (label, v, color) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _analyticsShareRow(
                label: label,
                value: '$v',
                share: share(v),
                color: color,
              ),
            ),
        ],
      ),
    );
  }

  Widget _analyticsRecentPayments(AdminDashboardStats? stats) {
    final items = stats?.recentPayments ?? const <AdminRecentPayment>[];
    final now = DateTime.now();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      decoration: adminCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _analyticsCardTitle(
            'Malipo ya karibuni',
            trailing: TextButton(
              onPressed: () => _navigate(AdminPageId.payments),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFF818CF8),
              ),
              child: const Text(
                'Ona yote',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Hakuna malipo bado.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AdminColors.textSecondary,
                ),
              ),
            ),
          for (final p in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  AdminAvatar(p.userName, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${_planLabel(p.planKey)} · ${adminTimeAgo(p.at, now)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AdminColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        fmtTzs(p.amount),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _paymentStatusPill(p.status),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _adminSessionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0x2210B981),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x3310B981)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.verified_user_rounded,
            color: Color(0xFF34D399),
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Umeunganishwa na seva',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                Text(
                  _sessionRemainingLabel(),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AdminColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_adminLogout()),
            child: const Text('Toka'),
          ),
        ],
      ),
    );
  }

  void _applyForceUpdateSettingsFromMap(Map<String, dynamic> settings) {
    bool asBool(Object? v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v?.toString().trim().toLowerCase() ?? '';
      return s == 'true' || s == '1' || s == 'yes' || s == 'on';
    }

    int asInt(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString().trim() ?? '') ?? 0;
    }

    String asStr(Object? v, [String fallback = '']) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? fallback : s;
    }

    _settings.forceUpdateEnabled = asBool(settings['force_update_enabled']);
    _settings.minAndroidBuild = asInt(settings['min_android_build']);
    _settings.minAndroidVersion = asStr(settings['min_android_version']);
    _settings.latestAndroidVersion = asStr(settings['latest_android_version']);
    _settings.latestAndroidBuild = asInt(settings['latest_android_build']);
    _settings.playStoreUrl = asStr(
      settings['play_store_url'],
      'https://play.google.com/store/apps/details?id=com.washatv',
    );
    _settings.updateTitle = asStr(settings['update_title'], 'Sasisha WASHA TV');
    _settings.updateMessage = asStr(
      settings['update_message'],
      'Toleo jipya linahitajika ili kuendelea kutumia app. Pakua kutoka Play Store kisha fungua tena.',
    );

    _settingsMinBuild.text = '${_settings.minAndroidBuild}';
    _settingsMinVersion.text = _settings.minAndroidVersion;
    _settingsLatestVersion.text = _settings.latestAndroidVersion;
    _settingsLatestBuild.text = '${_settings.latestAndroidBuild}';
    _settingsPlayStoreUrl.text = _settings.playStoreUrl;
    _settingsUpdateTitle.text = _settings.updateTitle;
    _settingsUpdateMessage.text = _settings.updateMessage;
  }

  // --- Settings ---
  Widget _pageSettings() {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: adminCardDecoration(),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AdminPageHeading('Mipangilio'),
                const SizedBox(height: 16),
                _adminSessionCard(),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0x22F43F5E),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x33F43F5E)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.person_off_rounded,
                            color: Color(0xFFFB7185),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Ondoa premium kwa watumiaji',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Chuja orodha ya watumiaji (premium), chagua unaotaka, kisha warudishe free. '
                        'Watapoteza ufikiaji wa malipo na muda wa msimamizi — watalazimika kulipa tena.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: AdminColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 14,
                            ),
                          ),
                          onPressed: _hasAdminSession
                              ? () => unawaited(_showBulkRevokePremiumDialog())
                              : null,
                          icon: const Icon(Icons.filter_list_rounded, size: 18),
                          label: const Text(
                            'Chuja & ondoa premium',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Jina la tovuti',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _settingsSiteName,
                  onChanged: (v) => _settings.siteName = v,
                  decoration: _inputDeco(),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Usajili wa premium umewashwa',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: _settings.subscriptionEnabled,
                  onChanged: (v) =>
                      setState(() => _settings.subscriptionEnabled = v),
                  activeThumbColor: AdminColors.accentPrimary,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Hali ya matengenezo',
                    style: TextStyle(fontSize: 13),
                  ),
                  value: _settings.maintenanceMode,
                  onChanged: (v) =>
                      setState(() => _settings.maintenanceMode = v),
                  activeThumbColor: AdminColors.accentPrimary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'WhatsApp (wasiliani)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _settingsWhatsapp,
                  keyboardType: TextInputType.phone,
                  onChanged: (v) => _settings.whatsappNumber = v,
                  decoration: _inputDeco().copyWith(
                    hintText: 'mf. +255712345678 au 0712345678',
                    prefixIcon: const Icon(
                      Icons.chat_rounded,
                      color: Color(0xFF22C55E),
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Nambari hii itaonekana kwenye Wasifu katika app ya mtumiaji na kutumika kuthibitisha WhatsApp.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: AdminColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0x22FB7185),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0x33FB7185)),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.system_update_alt_rounded,
                              color: Color(0xFFFB7185),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Lazima ku update app',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Washa mtumiaji asiyesasisha hawezi kuona channels wala kulipa — atalazimishwa kwenda Play Store kwanza. '
                          'Baada ya kuchapisha APK mpya, weka Build ya chini = versionCode mpya (sasa 11 kwa 1.0.10+11).',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.4,
                            color: AdminColors.textSecondary,
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _settings.forceUpdateEnabled,
                          onChanged: (v) =>
                              setState(() => _settings.forceUpdateEnabled = v),
                          title: const Text(
                            'Lazimisha kusasisha app',
                            style: TextStyle(fontSize: 13),
                          ),
                          activeThumbColor: const Color(0xFFFB7185),
                        ),
                        TextField(
                          controller: _settingsMinBuild,
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _settings.minAndroidBuild =
                              int.tryParse(v.trim()) ?? 0,
                          decoration: _inputDeco().copyWith(
                            labelText: 'Build ya chini (versionCode)',
                            hintText: '11',
                            prefixIcon: const Icon(
                              Icons.numbers_rounded,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _settingsMinVersion,
                          onChanged: (v) =>
                              _settings.minAndroidVersion = v.trim(),
                          decoration: _inputDeco().copyWith(
                            labelText: 'Toleo la chini',
                            hintText: '1.0.10',
                            prefixIcon: const Icon(
                              Icons.new_releases_outlined,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _settingsLatestVersion,
                          onChanged: (v) =>
                              _settings.latestAndroidVersion = v.trim(),
                          decoration: _inputDeco().copyWith(
                            labelText: 'Toleo jipya',
                            hintText: '1.0.10',
                            prefixIcon: const Icon(
                              Icons.upgrade_rounded,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _settingsLatestBuild,
                          keyboardType: TextInputType.number,
                          onChanged: (v) => _settings.latestAndroidBuild =
                              int.tryParse(v.trim()) ?? 0,
                          decoration: _inputDeco().copyWith(
                            labelText: 'Build jipya (hiari)',
                            hintText: '11',
                            prefixIcon: const Icon(
                              Icons.build_circle_outlined,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _settingsPlayStoreUrl,
                          onChanged: (v) => _settings.playStoreUrl = v.trim(),
                          decoration: _inputDeco().copyWith(
                            labelText: 'Play Store URL',
                            prefixIcon: const Icon(
                              Icons.shop_rounded,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _settingsUpdateTitle,
                          onChanged: (v) => _settings.updateTitle = v.trim(),
                          decoration: _inputDeco().copyWith(
                            labelText: 'Kichwa cha ujumbe',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _settingsUpdateMessage,
                          maxLines: 3,
                          onChanged: (v) => _settings.updateMessage = v.trim(),
                          decoration: _inputDeco().copyWith(
                            labelText: 'Ujumbe kwa mtumiaji',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _btnPrimary(
                  label: 'Hifadhi mipangilio',
                  icon: Icons.save,
                  onTap: () async {
                    final wa = _settingsWhatsapp.text.trim();
                    _settings.whatsappNumber = wa;
                    _settings.minAndroidBuild =
                        int.tryParse(_settingsMinBuild.text.trim()) ?? 0;
                    _settings.minAndroidVersion = _settingsMinVersion.text
                        .trim();
                    _settings.latestAndroidVersion = _settingsLatestVersion.text
                        .trim();
                    _settings.latestAndroidBuild =
                        int.tryParse(_settingsLatestBuild.text.trim()) ?? 0;
                    _settings.playStoreUrl =
                        _settingsPlayStoreUrl.text.trim().isEmpty
                        ? 'https://play.google.com/store/apps/details?id=com.washatv'
                        : _settingsPlayStoreUrl.text.trim();
                    _settings.updateTitle =
                        _settingsUpdateTitle.text.trim().isEmpty
                        ? 'Sasisha WASHA TV'
                        : _settingsUpdateTitle.text.trim();
                    _settings.updateMessage = _settingsUpdateMessage.text
                        .trim();
                    final sp = await SharedPreferences.getInstance();
                    await sp.setString(AdminPrefsKeys.supportWhatsapp, wa);
                    if (_hasAdminSession) {
                      try {
                        final res = await http
                            .patch(
                              Uri.parse('$_apiBase/api/v1/admin/settings'),
                              headers: _adminHeaders(),
                              body: jsonEncode({
                                'site_name': _settingsSiteName.text.trim(),
                                'subscription_enabled':
                                    _settings.subscriptionEnabled,
                                'maintenance_mode': _settings.maintenanceMode,
                                'whatsapp_number': wa,
                                'force_update_enabled':
                                    _settings.forceUpdateEnabled,
                                'min_android_build': _settings.minAndroidBuild,
                                'min_android_version':
                                    _settings.minAndroidVersion,
                                'latest_android_version':
                                    _settings.latestAndroidVersion,
                                'latest_android_build':
                                    _settings.latestAndroidBuild,
                                'play_store_url': _settings.playStoreUrl,
                                'update_title': _settings.updateTitle,
                                'update_message': _settings.updateMessage,
                              }),
                            )
                            .timeout(const Duration(seconds: 12));
                        if (res.statusCode < 200 || res.statusCode >= 300) {
                          throw Exception('settings ${res.statusCode}');
                        }
                      } catch (_) {
                        if (!mounted) return;
                        _showToast(
                          'Imeshindikana kuhifadhi mipangilio kwenye server.',
                          _ToastType.error,
                        );
                        return;
                      }
                    }
                    if (!mounted) return;
                    _showToast('Mabadiliko yamehifadhiwa.', _ToastType.success);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Logs ---
  Widget _pageLogs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AdminPageHeading('Kumbukumbu za shughuli'),
        const SizedBox(height: 12),
        _tableWrap(
          columns: const ['ID', 'Msimamizi', 'Kitendo', 'Tarehe'],
          rows: _logs.take(30).map((l) {
            return [
              Text(
                l.id,
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textSecondary,
                ),
              ),
              Text(l.adminName, style: const TextStyle(fontSize: 12)),
              _badge(_swLogAction(l.action), AdminColors.accentPrimary),
              Text(
                _formatLogDateTime(l.createdAt),
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textSecondary,
                ),
              ),
            ];
          }).toList(),
        ),
      ],
    );
  }

  Widget _tableWrap({
    required List<String> columns,
    required List<List<Widget>> rows,
  }) {
    return Container(
      decoration: adminCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return _HorizontalScroll(
            showThumb: constraints.maxWidth < 640,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(
                  AdminColors.bgSecondary,
                ),
                headingRowHeight: 42,
                dataRowMinHeight: 44,
                horizontalMargin: 8,
                columnSpacing: 10,
                headingTextStyle: const TextStyle(
                  color: AdminColors.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                columns: columns
                    .map((c) => DataColumn(label: Text(c.toUpperCase())))
                    .toList(),
                rows: rows
                    .map(
                      (cells) => DataRow(
                        cells: cells.map((w) => DataCell(w)).toList(),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pageTitleRow({
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminPageHeading(title),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AdminColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (action != null) action,
      ],
    );
  }

  InputDecoration _inputDeco() => InputDecoration(
    filled: true,
    fillColor: AdminColors.bgPrimary,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0x1AFFFFFF)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AdminColors.accentPrimary),
    ),
  );

  Widget _btnPrimary({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool small = false,
  }) {
    return AdminPressable(
      onTap: onTap,
      lift: 2,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: small ? 12 : 16,
          vertical: small ? 8 : 11,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D6366F1),
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: small ? 14 : 16, color: Colors.white),
            SizedBox(width: small ? 6 : 8),
            Text(
              label,
              style: TextStyle(
                fontSize: small ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btnOutline({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminColors.textSecondary,
        side: const BorderSide(color: Color(0x26FFFFFF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      icon: Icon(icon, size: 14),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Compose a push. [deviceId] pre-selects "one user" (opened from a user's card).
  void _modalSendNotification({String? deviceId}) {
    final title = TextEditingController();
    final msg = TextEditingController();
    final device = TextEditingController(text: deviceId ?? '');
    var target = deviceId == null || deviceId.isEmpty ? 'all' : 'user';
    var sending = false;
    const targets = <(String, String)>[
      ('all', 'Wote'),
      ('premium', 'Premium'),
      ('free', 'Bure'),
      ('user', 'Mtumiaji mmoja'),
    ];

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AdminColors.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Tuma arifa',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tuma kwa',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: targets.map((t) {
                      return ChoiceChip(
                        label: Text(t.$2),
                        selected: target == t.$1,
                        onSelected: sending
                            ? null
                            : (_) => setLocal(() => target = t.$1),
                      );
                    }).toList(),
                  ),
                  if (target == 'user') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: device,
                      decoration: _inputDeco().copyWith(
                        labelText: 'Device ID au USR id ya mtumiaji',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    maxLength: 100,
                    decoration: _inputDeco().copyWith(labelText: 'Kichwa'),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: msg,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: _inputDeco().copyWith(labelText: 'Ujumbe'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(ctx),
              child: const Text('Ghairi'),
            ),
            FilledButton.icon(
              onPressed: sending
                  ? null
                  : () async {
                      if (title.text.trim().isEmpty ||
                          msg.text.trim().isEmpty) {
                        _showToast('Andika kichwa na ujumbe', _ToastType.error);
                        return;
                      }
                      if (target == 'user' && device.text.trim().isEmpty) {
                        _showToast(
                          'Weka Device ID ya mtumiaji',
                          _ToastType.error,
                        );
                        return;
                      }
                      if (!_hasAdminSession) {
                        _showToast(
                          'Hujaingia (login) kama msimamizi',
                          _ToastType.error,
                        );
                        return;
                      }
                      setLocal(() => sending = true);
                      final done = await _sendNotification(
                        target: target,
                        title: title.text.trim(),
                        message: msg.text.trim(),
                        deviceId: device.text.trim(),
                      );
                      if (!ctx.mounted) return;
                      if (done) {
                        Navigator.pop(ctx);
                      } else {
                        setLocal(() => sending = false);
                      }
                    },
              icon: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(sending ? 'Inatuma…' : 'Tuma'),
            ),
          ],
        ),
      ),
    );
  }

  /// Returns true when the dialog can close (the server stored the attempt, even if delivery failed).
  Future<bool> _sendNotification({
    required String target,
    required String title,
    required String message,
    required String deviceId,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_apiBase/api/v1/admin/notifications'),
            headers: _adminHeaders(),
            body: jsonEncode({
              'title': title,
              'message': message,
              'type': 'info',
              'target': target,
              if (target == 'user') 'device_id': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 401 || res.statusCode == 403) {
        await _handleAdminUnauthorized();
        return false;
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        _showToast(
          _readApiError(res.body) ??
              'Kutuma kumeshindikana (${res.statusCode}).',
          _ToastType.error,
        );
        return false;
      }
      final out = (jsonDecode(res.body) as Map).cast<String, dynamic>();
      final delivery = _s(out['delivery'], fallback: 'sent');
      final err = _s(out['error']);
      switch (delivery) {
        case 'sent':
          _showToast(
            target == 'user' ? 'Arifa imemfikia mtumiaji.' : 'Arifa imetumwa!',
            _ToastType.success,
          );
        case 'bridge':
          _showToast('Arifa imetumwa kupitia Supasoka.', _ToastType.success);
        case 'not_configured':
          _showToast(
            err.isNotEmpty ? err : 'FCM haijasanidiwa kwenye seva.',
            _ToastType.warning,
          );
        default:
          _showToast(
            err.isNotEmpty ? 'Haikufika: $err' : 'Arifa haikufika.',
            _ToastType.error,
          );
      }
      unawaited(_reloadNotifications());
      return true;
    } catch (e) {
      _showToast('Hitilafu ya mtandao: $e', _ToastType.error);
      return false;
    }
  }
}

enum _ToastType { success, error, warning, info }

class _Toast {
  _Toast(this.message, this.type);
  final String message;
  final _ToastType type;
}

class _HamburgerButton extends StatelessWidget {
  const _HamburgerButton({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: open
              ? const Icon(
                  Icons.close,
                  key: ValueKey('c'),
                  size: 18,
                  color: Color(0xFF94A3B8),
                )
              : const Icon(
                  Icons.menu_rounded,
                  key: ValueKey('m'),
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
        ),
      ),
    );
  }
}

class _HorizontalScroll extends StatefulWidget {
  const _HorizontalScroll({required this.showThumb, required this.child});

  final bool showThumb;
  final Widget child;

  @override
  State<_HorizontalScroll> createState() => _HorizontalScrollState();
}

class _HorizontalScrollState extends State<_HorizontalScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: widget.showThumb,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        child: widget.child,
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.5, end: 1.0).animate(_c),
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Color(0xFFEF4444),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
