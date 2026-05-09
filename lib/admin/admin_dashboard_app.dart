import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_channel_categories.dart';
import '../services/pricing_catalog.dart';
import '../services/storage_service.dart';
import 'admin_colors.dart';
import 'admin_currency.dart';
import 'admin_data.dart';
import 'admin_models.dart';

enum _AccessUnit { hours, days, weeks, months }

/// Run with: `flutter run -t lib/main_admin.dart`
class WashaAdminApp extends StatelessWidget {
  const WashaAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: AdminColors.bgPrimary,
        textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
          bodyColor: AdminColors.textPrimary,
          displayColor: AdminColors.textPrimary,
        ),
        colorScheme: const ColorScheme.dark(
          primary: AdminColors.accentPrimary,
          surface: AdminColors.bgSecondary,
        ),
      ),
      home: const _AdminScaffold(),
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

class _AdminScaffold extends StatefulWidget {
  const _AdminScaffold();

  @override
  State<_AdminScaffold> createState() => _AdminScaffoldState();
}

class _AdminScaffoldState extends State<_AdminScaffold> {
  final _rand = Random();
  final _globalSearch = TextEditingController();
  final _userSearch = TextEditingController();
  /// Same Railway API as the viewer app unless overridden with `--dart-define=WASHA_API_BASE_URL=...`.
  final String _apiBase = const String.fromEnvironment(
    'WASHA_API_BASE_URL',
    defaultValue: 'https://washatv-production.up.railway.app',
  ).replaceAll(RegExp(r'/+$'), '');
  final String _adminApiKey = const String.fromEnvironment('WASHA_ADMIN_API_KEY');

  late List<AdminUser> _users;
  late List<AdminChannel> _channels;
  late List<AdminSlide> _slides;
  late List<AdminSubscription> _subscriptions;
  late List<AdminPayment> _payments;
  late List<AdminNotification> _notifications;
  late List<AdminLog> _logs;
  late Map<String, PricingPlan> _pricing;
  final _settings = AdminSettings();
  /// Field initializers run on first read — survives hot reload when `initState` does not re-run.
  late final TextEditingController _settingsSiteName = TextEditingController(text: _settings.siteName);
  late final TextEditingController _settingsWhatsapp = TextEditingController(text: _settings.whatsappNumber);

  AdminPageId _page = AdminPageId.dashboard;
  String? _slideQuery = '';
  String? _slideFilter = 'all';
  /// Desktop: whether sidebar is open (main gets left margin). HTML starts with main `full-width` → sidebar closed.
  bool _sidebarOpen = false;
  final List<_Toast> _toasts = [];

  bool get _isMobile => MediaQuery.sizeOf(context).width < 1024;

  @override
  void initState() {
    super.initState();
    _users = generateUsers(_rand);
    _channels = generateChannels(_rand);
    _slides = generateSlides();
    _pricing = defaultPricingPlans();
    _subscriptions = generateSubscriptions(_rand, _users, _pricing);
    _payments = generatePayments(_rand, _users);
    _notifications = staticNotifications();
    _logs = generateLogs(_rand);
    _loadSavedPricing();
    _loadSavedSettings();
    _hydrateFromBackend();
  }

  Future<void> _loadSavedSettings() async {
    final sp = await SharedPreferences.getInstance();
    final wa = sp.getString(StorageService.supportWhatsappPrefsKey);
    if (!mounted || wa == null || wa.isEmpty) return;
    setState(() {
      _settings.whatsappNumber = wa;
      _settingsWhatsapp.text = wa;
    });
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
            _pricing[e.key] = _pricingFromJson(e.value as Map<String, dynamic>, _pricing[e.key]!);
          }
        }
      });
    } catch (_) {}
  }

  Map<String, String> _adminHeaders() {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_adminApiKey.isNotEmpty) h['X-Admin-Key'] = _adminApiKey;
    return h;
  }

  Future<void> _hydrateFromBackend() async {
    try {
      final bootstrapRes = await http.get(Uri.parse('$_apiBase/api/v1/public/bootstrap')).timeout(const Duration(seconds: 12));
      if (bootstrapRes.statusCode < 200 || bootstrapRes.statusCode >= 300) return;
      final map = jsonDecode(bootstrapRes.body) as Map<String, dynamic>;
      final rawPlans = (map['plans'] as List?)?.cast<dynamic>() ?? const [];
      final rawChannels = (map['channels'] as List?)?.cast<dynamic>() ?? const [];
      final rawSlidesFromBootstrap = (map['slides'] as List?)?.cast<dynamic>() ?? const [];
      final settings = (map['settings'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};

      List<AdminUser>? serverUsers;
      List<AdminSlide>? serverSlides;
      List<AdminPayment>? serverPayments;
      List<AdminNotification>? serverNotifications;

      if (_adminApiKey.isNotEmpty) {
        try {
          final usersRes = await http.get(Uri.parse('$_apiBase/api/v1/admin/users'), headers: _adminHeaders()).timeout(const Duration(seconds: 12));
          final slidesRes = await http.get(Uri.parse('$_apiBase/api/v1/admin/slides'), headers: _adminHeaders()).timeout(const Duration(seconds: 12));
          final txRes = await http.get(Uri.parse('$_apiBase/api/v1/admin/transactions'), headers: _adminHeaders()).timeout(const Duration(seconds: 12));
          final notiRes = await http.get(Uri.parse('$_apiBase/api/v1/admin/notifications'), headers: _adminHeaders()).timeout(const Duration(seconds: 12));
          if (usersRes.statusCode >= 200 && usersRes.statusCode < 300) {
            final usersMap = jsonDecode(usersRes.body) as Map<String, dynamic>;
            final rawUsers = (usersMap['users'] as List?)?.cast<dynamic>() ?? const [];
            serverUsers = rawUsers.whereType<Map>().map((raw) {
              final j = raw.cast<String, dynamic>();
              return AdminUser(
                id: _s(j['id']),
                name: _s(j['name'], fallback: 'Viewer'),
                phone: _s(j['phone'], fallback: 'N/A'),
                deviceId: _s(j['device_id']),
                status: _s(j['status'], fallback: 'active'),
                subscription: _s(j['subscription'], fallback: 'free'),
                createdAt: _dt(j['created_at']) ?? DateTime.now(),
                adminAccessUntil: _dt(j['admin_access_until']),
              );
            }).toList();
          }
          if (slidesRes.statusCode >= 200 && slidesRes.statusCode < 300) {
            final slidesMap = jsonDecode(slidesRes.body) as Map<String, dynamic>;
            final raw = (slidesMap['slides'] as List?)?.cast<dynamic>() ?? const [];
            serverSlides = raw.whereType<Map>().map((rawItem) {
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
            }).toList();
          }
          if (txRes.statusCode >= 200 && txRes.statusCode < 300) {
            final txMap = jsonDecode(txRes.body) as Map<String, dynamic>;
            final raw = (txMap['transactions'] as List?)?.cast<dynamic>() ?? const [];
            serverPayments = raw.whereType<Map>().map((rawItem) {
              final j = rawItem.cast<String, dynamic>();
              return AdminPayment(
                id: _s(j['id']),
                userName: _s(j['user_name'], fallback: 'Viewer'),
                amount: (j['amount'] as num?)?.toDouble() ?? 0,
                method: _s(j['method'], fallback: 'N/A'),
                status: _s(j['status'], fallback: 'completed'),
                transactionId: _s(j['provider_ref'], fallback: _s(j['id'])),
                createdAt: _dt(j['created_at']) ?? DateTime.now(),
              );
            }).toList();
          }
          if (notiRes.statusCode >= 200 && notiRes.statusCode < 300) {
            final nMap = jsonDecode(notiRes.body) as Map<String, dynamic>;
            final raw = (nMap['notifications'] as List?)?.cast<dynamic>() ?? const [];
            serverNotifications = raw.whereType<Map>().map((rawItem) {
              final j = rawItem.cast<String, dynamic>();
              return AdminNotification(
                id: _s(j['id']),
                title: _s(j['title']),
                message: _s(j['message']),
                type: _s(j['type'], fallback: 'info'),
                read: j['read'] as bool? ?? false,
                createdAt: _dt(j['created_at']) ?? DateTime.now(),
              );
            }).toList();
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        for (final p in rawPlans) {
          if (p is! Map) continue;
          final j = p.cast<String, dynamic>();
          final key = _s(j['plan_key']);
          final existing = _pricing[key];
          if (existing == null) continue;
          final price = (j['price'] as num?)?.toDouble();
          final days = (j['duration_days'] as num?)?.toInt();
          final enabled = j['enabled'] as bool?;
          final name = (j['name'] as String?)?.trim();
          if (name != null && name.isNotEmpty) existing.name = name;
          if (price != null) existing.price = price;
          existing.originalPrice = existing.price;
          existing.discount = 0;
          if (days != null) existing.duration = days;
          if (enabled != null) existing.enabled = enabled;
        }
        _channels = rawChannels.whereType<Map>().map((raw) {
          final j = raw.cast<String, dynamic>();
          final category = _s(j['category']);
          return AdminChannel(
            id: _s(j['id']),
            name: _s(j['name']),
            category: category.isEmpty ? kAppChannelCategories.first : category,
            premium: j['premium'] as bool? ?? false,
            live: j['live'] as bool? ?? false,
            status: _s(j['status'], fallback: 'active'),
            thumbnail: _s(j['thumbnail']),
            viewers: (j['viewers'] as num?)?.toInt() ?? 0,
            rating: _s(j['rating'], fallback: '5.0'),
            drm: _s(j['drm'], fallback: 'none'),
          );
        }).where((c) => c.id.isNotEmpty && c.name.isNotEmpty).toList();
        if (serverUsers != null) _users = serverUsers!;
        if (serverSlides != null) {
          _slides = serverSlides!;
        } else {
          _slides = rawSlidesFromBootstrap.whereType<Map>().map((rawItem) {
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
          }).where((s) => s.id.isNotEmpty && s.title.isNotEmpty && s.imageUrl.isNotEmpty).toList();
        }
        if (serverPayments != null) _payments = serverPayments!;
        if (serverNotifications != null) _notifications = serverNotifications!;
        final wa = _s(settings['whatsapp_number']);
        _settings.whatsappNumber = wa;
        _settingsWhatsapp.text = wa;
      });
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_persistPricingMapToPrefs());
        });
      }
    } catch (_) {
      // Local mode fallback.
    }
  }

  Future<void> _persistPricingMapToPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final map = {for (final e in _pricing.entries) e.key: _pricingToJson(e.value)};
      await sp.setString('washatvPricing', jsonEncode(map));
    } catch (_) {}
  }

  String _s(Object? value, {String fallback = ''}) => value?.toString().trim() ?? fallback;
  DateTime? _dt(Object? value) {
    final s = value?.toString();
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  PricingPlan _pricingFromJson(Map<String, dynamic> j, PricingPlan fallback) {
    return PricingPlan(
      name: j['name'] as String? ?? fallback.name,
      originalPrice: (j['originalPrice'] as num?)?.toDouble() ?? fallback.originalPrice,
      price: (j['price'] as num?)?.toDouble() ?? fallback.price,
      discount: (j['discount'] as num?)?.toInt() ?? fallback.discount,
      duration: (j['duration'] as num?)?.toInt() ?? fallback.duration,
      features: (j['features'] as List<dynamic>?)?.map((e) => e as String).toList() ?? fallback.features,
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
    _settingsSiteName.dispose();
    _settingsWhatsapp.dispose();
    _globalSearch.dispose();
    _userSearch.dispose();
    super.dispose();
  }

  void _navigate(AdminPageId p) {
    setState(() {
      _page = p;
      if (_isMobile) _sidebarOpen = false;
    });
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!mobile)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.ease,
                  width: _sidebarOpen ? 260 : 0,
                  child: _sidebarOpen
                      ? ClipRect(
                          child: _buildSidebar(mobile),
                        )
                      : const SizedBox.shrink(),
                ),
              Expanded(
                child: Column(
                  children: [
                    _buildHeader(mobile, w),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, mobile ? 88 : 16),
                        child: _buildPage(),
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
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 20)]),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                t.type == _ToastType.success ? Icons.check_circle_outline : t.type == _ToastType.error ? Icons.cancel_outlined : Icons.info_outline,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(t.message, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildHeader(bool mobile, double width) {
    final showBrand = width >= 640;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xF20A0E17),
        border: Border(bottom: BorderSide(color: AdminColors.borderSubtle)),
      ),
      child: Row(
        children: [
          _HamburgerButton(open: _sidebarOpen, onTap: _toggleSidebar),
          const SizedBox(width: 12),
          if (showBrand)
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF818CF8), Color(0xFFA78BFA)]).createShader(r),
              child: const Text('WASHA TV', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white)),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _globalSearch,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF6B7280)),
                  filled: true,
                  fillColor: AdminColors.bgPrimary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1))),
                ),
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: () => _navigate(AdminPageId.notifications),
                icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF9CA3AF)),
              ),
              const Positioned(right: 10, top: 10, child: _PulseDot()),
            ],
          ),
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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF9333EA)]),
                  ),
                  child: const Icon(Icons.bolt, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF818CF8), Color(0xFFA78BFA)]).createShader(r),
                        child: const Text('WASHA Admin', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
                      ),
                      const Text('Control Panel v2.0', style: TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
                if (mobileCloseBtn)
                  IconButton(
                    onPressed: () => setState(() => _sidebarOpen = false),
                    icon: const Icon(Icons.close, color: Color(0xFF9CA3AF)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _navRow(AdminPageId.dashboard, Icons.dashboard_rounded, 'Dashboard'),
                _navRow(AdminPageId.users, Icons.groups_rounded, 'Users'),
                _navRow(AdminPageId.channels, Icons.satellite_alt_rounded, 'Channels'),
                _navRow(AdminPageId.slides, Icons.slideshow_rounded, 'Slides'),
                _navRow(AdminPageId.subscriptions, Icons.workspace_premium_rounded, 'Subscriptions'),
                _navRow(AdminPageId.pricing, Icons.sell_rounded, 'Pricing Plans'),
                _navRow(AdminPageId.payments, Icons.credit_card_rounded, 'Payments'),
                _navRow(AdminPageId.notifications, Icons.notifications_rounded, 'Notifications'),
                _navRow(AdminPageId.analytics, Icons.show_chart_rounded, 'Analytics'),
                _navRow(AdminPageId.settings, Icons.settings_rounded, 'Settings'),
                _navRow(AdminPageId.logs, Icons.history_rounded, 'Activity Logs'),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AdminColors.borderSubtle))),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFFFBBF24), Color(0xFFF97316)]),
                  ),
                  alignment: Alignment.center,
                  child: const Text('SA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Super Admin', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Text('admin@washatv.com', style: TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _showToast('Logging out...', _ToastType.warning),
                  icon: const Icon(Icons.logout, size: 18, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navRow(AdminPageId id, IconData icon, String label) {
    final active = _page == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: active ? const Color(0x1F6366F1) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _navigate(id),
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: active ? AdminColors.accentPrimary : Colors.transparent, width: 3)),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(width: 24, child: Icon(icon, size: 18, color: active ? AdminColors.accentPrimary : const Color(0xFF94A3B8))),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontSize: 13, color: active ? AdminColors.accentPrimary : AdminColors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomNav() {
    const items = <(AdminPageId, IconData, String)>[
      (AdminPageId.dashboard, Icons.dashboard_rounded, 'Dashboard'),
      (AdminPageId.users, Icons.groups_rounded, 'Users'),
      (AdminPageId.channels, Icons.satellite_alt_rounded, 'Channels'),
      (AdminPageId.slides, Icons.slideshow_rounded, 'Slides'),
      (AdminPageId.pricing, Icons.sell_rounded, 'Pricing'),
      (AdminPageId.settings, Icons.settings_rounded, 'Settings'),
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(4, 8, 4, 8 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Color(0xF2111827),
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.map((e) {
          final active = _page == e.$1;
          return Expanded(
            child: InkWell(
              onTap: () => _navigate(e.$1),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: active ? const Color(0x1F6366F1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(e.$2, size: 16, color: active ? AdminColors.accentPrimary : const Color(0xFF6B7280)),
                    const SizedBox(height: 4),
                    Text(e.$3, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: active ? AdminColors.accentPrimary : const Color(0xFF6B7280))),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPage() {
    switch (_page) {
      case AdminPageId.dashboard:
        return _pageDashboard();
      case AdminPageId.users:
        return _pageUsers();
      case AdminPageId.channels:
        return _pageChannels();
      case AdminPageId.slides:
        return _pageSlides();
      case AdminPageId.subscriptions:
        return _pageSubscriptions();
      case AdminPageId.pricing:
        return _pagePricing();
      case AdminPageId.payments:
        return _pagePayments();
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
    final totalUsers = _users.length;
    final premiumUsers = _users.where((u) => u.effectivePremium).length;
    final activeChannels = _channels.where((c) => c.status == 'active').length;
    final revenue = _payments.where((p) => p.status == 'completed').fold<double>(0, (a, b) => a + b.amount);
    final recentUsers = _users.take(5).toList();
    final recentPayments = _payments.where((p) => p.status == 'completed').take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageTitleRow(
          title: 'Admin Dashboard',
          subtitle: 'Welcome back, Super Admin',
          action: _btnPrimary(label: 'Add Channel', icon: Icons.add, onTap: () => _showChannelEditor()),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth < 640 ? 2 : 4;
            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: cols == 2 ? 1.12 : 1.28,
              children: [
                _statCard(label: 'Total Users', value: '$totalUsers', icon: Icons.groups_rounded, iconBg: const Color(0x336366F1), iconColor: const Color(0xFF818CF8)),
                _statCard(label: 'Premium', value: '$premiumUsers', icon: Icons.workspace_premium_rounded, iconBg: const Color(0x33F59E0B), iconColor: const Color(0xFFFBBF24)),
                _statCard(label: 'Channels', value: '$activeChannels', icon: Icons.satellite_alt_rounded, iconBg: const Color(0x3310B981), iconColor: const Color(0xFF34D399)),
                _statCard(label: 'Revenue', value: fmtTzs(revenue), icon: Icons.attach_money_rounded, iconBg: const Color(0x33A855F7), iconColor: const Color(0xFFC084FC)),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 1024;
            final charts = [
              _chartCard('User Growth', 300, _userGrowthChart()),
              _chartCard('Revenue Overview (TSh)', 300, _revenueBarChart()),
            ];
            if (stacked) {
              return Column(children: [charts[0], const SizedBox(height: 16), charts[1]]);
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
                title: 'Recent Users',
                onViewAll: () => _navigate(AdminPageId.users),
                columnFlex: const [5, 2, 2, 2],
                columns: const ['User', 'Status', 'Plan', 'Date'],
                rows: recentUsers
                    .map(
                      (u) => [
                        _userCell(u.name),
                        _compactPill(u.status, u.status == 'active' ? AdminColors.accentSuccess : AdminColors.accentDanger),
                        _compactPill(u.effectivePremium ? 'premium' : 'free', u.effectivePremium ? AdminColors.accentWarning : const Color(0xFF6B7280)),
                        _recentCellText(_fmtDate(u.createdAt), color: AdminColors.textSecondary),
                      ],
                    )
                    .toList(),
              ),
              _recentTableCard(
                title: 'Recent Payments',
                onViewAll: () => _navigate(AdminPageId.payments),
                columnFlex: const [4, 2, 2, 2],
                columns: const ['User', 'Amount', 'Status', 'Date'],
                rows: recentPayments
                    .map(
                      (p) => [
                        _recentCellText(p.userName, weight: FontWeight.w500),
                        _recentCellText(fmtTzs(p.amount), weight: FontWeight.w800),
                        _paymentStatusPill(p.status),
                        _recentCellText(_fmtDate(p.createdAt), color: AdminColors.textSecondary),
                      ],
                    )
                    .toList(),
              ),
            ];
            if (stacked) {
              return Column(children: [blocks[0], const SizedBox(height: 16), blocks[1]]);
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

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AdminColors.bgTertiary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          const headerH = 30.0;
          final valueH = max(12.0, c.maxHeight - headerH);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: headerH,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AdminColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, height: 1.15),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                      child: Icon(icon, color: iconColor, size: 16),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: valueH,
                width: double.infinity,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chartCard(String title, double height, Widget chart) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.bgTertiary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 16),
          SizedBox(height: height, child: chart),
        ],
      ),
    );
  }

  Widget _userGrowthChart() {
    const labels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul'];
    const zeroSpots = <FlSpot>[
      FlSpot(0, 0),
      FlSpot(1, 0),
      FlSpot(2, 0),
      FlSpot(3, 0),
      FlSpot(4, 0),
      FlSpot(5, 0),
      FlSpot(6, 0),
    ];
    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 200, getDrawingHorizontalLine: (_) => FlLine(color: const Color(0x08FFFFFF), strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              reservedSize: 28,
              getTitlesWidget: (v, m) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(labels[v.toInt().clamp(0, 6)], style: const TextStyle(color: AdminColors.textSecondary, fontSize: 10)),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (v, m) => Text(
                v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v.toInt().toString(),
                style: const TextStyle(color: AdminColors.textSecondary, fontSize: 10),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: zeroSpots,
            isCurved: true,
            color: AdminColors.accentPrimary,
            barWidth: 2,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: const Color(0x146366F1)),
          ),
          LineChartBarData(
            spots: zeroSpots,
            isCurved: true,
            color: AdminColors.accentWarning,
            barWidth: 2,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: const Color(0x14F59E0B)),
          ),
        ],
        minX: 0,
        maxX: 6,
        minY: 0,
      ),
    );
  }

  Widget _revenueBarChart() {
    const labels = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul'];
    const vals = <double>[0, 0, 0, 0, 0, 0, 0];
    return BarChart(
      BarChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: const Color(0x08FFFFFF), strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        maxY: 1,
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, m) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(labels[v.toInt().clamp(0, 6)], style: const TextStyle(color: AdminColors.textSecondary, fontSize: 10)),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (v, m) => Text(
                fmtTzsAxis(v),
                style: const TextStyle(color: AdminColors.textSecondary, fontSize: 10),
              ),
            ),
          ),
        ),
        barGroups: List.generate(
          7,
          (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: vals[i],
                color: const Color(0xB36366F1),
                width: 18,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
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
    assert(columns.length == columnFlex.length, 'columnFlex must match columns');
    for (final r in rows) {
      assert(r.length == columns.length, 'row length must match columns');
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.bgTertiary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
              TextButton(
                onPressed: onViewAll,
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: const Text('View All', style: TextStyle(fontSize: 10, color: Color(0xFF818CF8))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _recentTableHeaderRow(columns, columnFlex),
          const Divider(height: 1, color: Color(0x14FFFFFF)),
          const SizedBox(height: 4),
          ...rows.map((cells) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _recentDataRow(cells, columnFlex),
              )),
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
              style: const TextStyle(color: AdminColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.3),
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
      style: TextStyle(fontSize: 12, fontWeight: weight, color: color ?? AdminColors.textPrimary),
    );
  }

  /// Scales down in very narrow cells so status text (e.g. "completed") is never clipped.
  Widget _compactPill(String text, Color color) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999)),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color, height: 1.1),
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
    return _compactPill(status, c);
  }

  Widget _userCell(String name) {
    final ini = name.length >= 2 ? name.substring(0, 2).toUpperCase() : name.toUpperCase();
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF9333EA)]),
          ),
          alignment: Alignment.center,
          child: Text(ini, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white)),
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  String _fmtDate(DateTime d) => MaterialLocalizations.of(context).formatCompactDate(d);

  String _formatLogDateTime(DateTime d) {
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${t(d.month)}-${t(d.day)} ${t(d.hour)}:${t(d.minute)}';
  }

  // --- Users ---
  Widget _pageUsers() {
    final q = _userSearch.text.toLowerCase();
    final filtered = _users.where((u) {
      if (q.isEmpty) return true;
      final blob = '${u.name} ${u.phone} ${u.displayDeviceId} ${u.status} ${u.subscription} ${u.id}'.toLowerCase();
      return blob.contains(q);
    }).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wideHeader = constraints.maxWidth >= 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wideHeader)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Users', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                        Text(
                          '${_users.length} total · Device ID = kitambulisho cha Wasifu kwenye app',
                          style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: min(280, constraints.maxWidth * 0.42),
                    child: TextField(
                      controller: _userSearch,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Tafuta jina, simu, device ID...',
                        filled: true,
                        fillColor: AdminColors.bgPrimary,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              const Text('Users', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              Text(
                '${_users.length} total · Device ID = Wasifu',
                style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _userSearch,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Tafuta jina, simu, device ID...',
                  filled: true,
                  fillColor: AdminColors.bgPrimary,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
                ),
              ),
            ],
            const SizedBox(height: 14),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _userCard(filtered[i]),
            ),
          ],
        );
      },
    );
  }

  Widget _userCard(AdminUser u) {
    final id = u.displayDeviceId;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2332), Color(0xFF151C28)],
        ),
        border: Border.all(color: const Color(0x14FFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x28000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    u.name.length >= 2 ? u.name.substring(0, 2).toUpperCase() : u.name.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(u.id, style: const TextStyle(fontSize: 10, color: AdminColors.textSecondary)),
                    ],
                  ),
                ),
                _badge(u.status, u.status == 'active' ? AdminColors.accentSuccess : AdminColors.accentDanger),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0x12FFFFFF))),
              child: Row(
                children: [
                  const Icon(Icons.smartphone_rounded, size: 16, color: Color(0xFF818CF8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      id,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFE2E8F0), height: 1.25),
                    ),
                  ),
                  Material(
                    color: const Color(0x226366F1),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: id));
                        _showToast('Device ID imenakiliwa', _ToastType.success);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, size: 14, color: Color(0xFF818CF8)),
                            SizedBox(width: 4),
                            Text('Nakili', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF818CF8))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _miniLabel(Icons.phone_rounded, u.phone),
                _planBadgeCell(u),
                _adminAccessInline(u),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0x14FFFFFF)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.start,
              children: [
                _userActionChip(
                  icon: Icons.edit_outlined,
                  label: 'Jina',
                  color: const Color(0xFF818CF8),
                  onTap: () async {
                    final n = await _promptText('Badilisha jina', u.name);
                    if (n != null && n.isNotEmpty) {
                      setState(() => u.name = n);
                      try {
                        await _syncUserToBackend(u, {'name': n});
                      } catch (_) {}
                    }
                    if (n != null && n.isNotEmpty) _showToast('Imehakikiwa', _ToastType.success);
                  },
                ),
                _userActionChip(
                  icon: Icons.schedule_rounded,
                  label: 'Muda wa premium',
                  color: const Color(0xFF34D399),
                  onTap: u.status == 'suspended' ? null : () => _showGrantAccessDialog(u),
                ),
                _userActionChip(
                  icon: Icons.workspace_premium_outlined,
                  label: u.subscription == 'premium' ? 'Malipo: ON' : 'Malipo: OFF',
                  color: u.subscription == 'premium' ? const Color(0xFFFBBF24) : const Color(0xFF6B7280),
                  onTap: () async {
                    final next = u.subscription == 'premium' ? 'free' : 'premium';
                    setState(() => u.subscription = next);
                    try {
                      await _syncUserToBackend(u, {'subscription': next});
                    } catch (_) {}
                    _showToast('Mfumo: ${u.subscription}', _ToastType.success);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniLabel(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0x22000000), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AdminColors.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _adminAccessInline(AdminUser u) {
    final end = u.adminAccessUntil;
    if (end == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: const Color(0x22000000), borderRadius: BorderRadius.circular(10)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_off_outlined, size: 14, color: Color(0xFF6B7280)),
            SizedBox(width: 6),
            Text('Msimamizi: —', style: TextStyle(fontSize: 11, color: AdminColors.textSecondary)),
          ],
        ),
      );
    }
    if (!end.isAfter(DateTime.now())) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: const Color(0x22000000), borderRadius: BorderRadius.circular(10)),
        child: const Text('Msimamizi: Imeisha', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0x2234D399), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0x2234D399))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_rounded, size: 14, color: Color(0xFF34D399)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${_humanRemaining(end)} · hadi ${_fmtAccessDate(end)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Color(0xFFBEF264), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _userActionChip({required IconData icon, required String label, required Color color, VoidCallback? onTap}) {
    return Material(
      color: const Color(0x18FFFFFF),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: onTap == null ? const Color(0xFF4B5563) : color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onTap == null ? const Color(0xFF4B5563) : Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _planBadgeCell(AdminUser u) {
    final premium = u.effectivePremium;
    final paid = u.subscription == 'premium';
    final adm = u.adminAccessActive;
    String? source;
    if (paid && adm) {
      source = 'Malipo + msimamizi';
    } else if (paid) {
      source = 'Malipo (mifumo)';
    } else if (adm) {
      source = 'Msimamizi pekee';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _badge(premium ? 'premium' : 'free', premium ? AdminColors.accentWarning : const Color(0xFF6B7280)),
        if (source != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              source,
              style: const TextStyle(fontSize: 9, color: AdminColors.textSecondary, height: 1.2),
            ),
          ),
      ],
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

  Future<void> _syncUserToBackend(AdminUser u, Map<String, dynamic> patch) async {
    if (_adminApiKey.isEmpty) return;
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
  }

  Future<void> _applyAdminDuration(AdminUser u, Duration add) async {
    final now = DateTime.now();
    final prev = u.adminAccessUntil;
    final base = (prev != null && prev.isAfter(now)) ? prev : now;
    final next = base.add(add);
    setState(() => u.adminAccessUntil = next);
    try {
      await _syncUserToBackend(u, {'admin_access_until': next.toIso8601String()});
    } catch (_) {}
    _showToast('Umeongeza muda wa premium (msimamizi)', _ToastType.success);
  }

  Future<void> _clearAdminAccess(AdminUser u) async {
    setState(() => u.adminAccessUntil = null);
    try {
      await _syncUserToBackend(u, {'admin_access_until': null});
    } catch (_) {}
    _showToast('Muda wa msimamizi umeondolewa', _ToastType.info);
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Ghairi')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Pa premium kwa muda', style: TextStyle(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Mtumiaji: ${u.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SelectableText(
                    'Device ID: ${u.displayDeviceId}',
                    style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    u.adminAccessActive
                        ? 'Muda wa sasa wa msimamizi unaisha: ${_fmtAccessDate(u.adminAccessUntil!)}. Mpya utaongezwa juu ya hii.'
                        : 'Hakuna muda wa msimamizi unaofanya kazi. Unaanza kutoka sasa.',
                    style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  const Text('Vinjari haraka', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _presetChip(ctx, u, 'Saa 1', const Duration(hours: 1)),
                      _presetChip(ctx, u, 'Masaa 6', const Duration(hours: 6)),
                      _presetChip(ctx, u, 'Siku 1', const Duration(days: 1)),
                      _presetChip(ctx, u, 'Siku 7', const Duration(days: 7)),
                      _presetChip(ctx, u, 'Siku 30', const Duration(days: 30)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Maongezi ya kujitegemea', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: TextField(
                          controller: customAmount,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13),
                          decoration: _inputDeco().copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
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
                            DropdownMenuItem(value: _AccessUnit.hours, child: Text('Saa')),
                            DropdownMenuItem(value: _AccessUnit.days, child: Text('Siku')),
                            DropdownMenuItem(value: _AccessUnit.weeks, child: Text('Wiki')),
                            DropdownMenuItem(value: _AccessUnit.months, child: Text('Mwezi (30 siku)')),
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
                        message: 'Muda wa premium wa “${u.name}” utaondolewa mara moja.',
                      );
                      if (!mounted || !ok) return;
                      await _clearAdminAccess(u);
                      Navigator.pop(ctx);
                    }
                  : null,
              child: const Text('Futa muda wa msimamizi'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Funga')),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
  }

  // --- Channels ---
  Widget _pageChannels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Channels', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  Text('${_channels.length} channels', style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                ],
              ),
            ),
            _btnPrimary(label: 'Add', icon: Icons.add, small: true, onTap: () => _showChannelEditor()),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final cross = c.maxWidth > 900 ? 4 : (c.maxWidth > 520 ? 3 : 2);
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cross, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.82),
              itemCount: _channels.length,
              itemBuilder: (context, i) {
                final ch = _channels[i];
                return Container(
                  decoration: BoxDecoration(
                    color: AdminColors.bgTertiary,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x0DFFFFFF)),
                  ),
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
                              errorBuilder: (_, __, ___) => _imageFallback(Icons.tv, 'Hakuna picha'),
                            ),
                            if (ch.status != 'active')
                              Positioned.fill(
                                child: Container(
                                  color: const Color(0x66000000),
                                  alignment: Alignment.center,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(color: const Color(0xE61F2937), borderRadius: BorderRadius.circular(8)),
                                    child: const Text('INACTIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: Colors.white)),
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (ch.premium) _tinyBadge('Premium', const Color(0xFFF59E0B), darkText: true),
                                  if (ch.live) ...[const SizedBox(width: 4), _tinyBadge('LIVE', const Color(0xFFEF4444))],
                                ],
                              ),
                            ),
                            if (ch.effectiveDrm != 'none')
                              Positioned(
                                top: 8,
                                left: 8,
                                child: _tinyBadge(_channelDrmShort(ch.effectiveDrm), const Color(0xFF4F46E5)),
                              ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xCC000000)]),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white)),
                                    Text(ch.category, style: const TextStyle(fontSize: 9, color: Color(0xFFD1D5DB))),
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
                            Text('⭐${ch.rating}', style: const TextStyle(fontSize: 9, color: AdminColors.textSecondary)),
                            const Spacer(),
                            IconButton(
                              onPressed: () => _showChannelEditor(index: i),
                              icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF818CF8)),
                              tooltip: 'Edit channel',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              visualDensity: VisualDensity.compact,
                            ),
                            IconButton(
                              onPressed: () => _confirmDeleteChannel(i),
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFF87171)),
                              tooltip: 'Delete channel',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  // --- Slides ---
  Widget _pageSlides() {
    final slides = [..._slides]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final activeCount = slides.where((s) => s.active).length;
    final premiumCount = slides.where((s) => s.premium).length;
    final slideQuery = _slideQuery ?? '';
    final slideFilter = _slideFilter ?? 'all';
    final q = slideQuery.trim().toLowerCase();
    final filtered = slides.where((s) {
      final byQuery = q.isEmpty || s.title.toLowerCase().contains(q) || s.subtitle.toLowerCase().contains(q) || s.id.toLowerCase().contains(q);
      final byFilter = switch (slideFilter) {
        'active' => s.active,
        'inactive' => !s.active,
        'premium' => s.premium,
        _ => true,
      };
      return byQuery && byFilter;
    }).toList();

    /// Full list visible only with no filters — reorder updates `sort_order` on all slides.
    final canReorderSlides = q.isEmpty && slideFilter == 'all' && filtered.length >= 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// Dev-only banner: release IPAs/APKs built with [--dart-define-from-file] omit this panel.
        if (_adminApiKey.isEmpty && !kReleaseMode)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0x33451A03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x66EA580C)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.key_off_rounded, size: 20, color: Color(0xFFFDBA74)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Slides hazihifadhiwi kwa databesi bila ufunguo wa admin. '
                      'Weka thamani ya ADMIN_API_KEY ya Railway ndani ya WASHA_ADMIN_API_KEY kwenye admin/dev_defines.json. '
                      'MUHIMU: lazima uendeshe na --dart-define-from-file (si flutter run tu). '
                      'Kutoka mzizi wa mradi: flutter run -t lib/main_admin.dart -d chrome '
                      '--dart-define-from-file=admin/dev_defines.json. '
                      'Ukikatika folda admin/: flutter run -d chrome --dart-define-from-file=dev_defines.json '
                      'au bash admin/run_admin_chrome.sh. '
                      'Run & Debug: \"Admin · Chrome\" au \"Admin · Chrome (cwd admin/)\". '
                      'IPA: bash admin/build_ipa.sh. '
                      'Server na migrations lazima ziwe tayari.',
                      style: TextStyle(fontSize: 12, height: 1.38, color: Color(0xFFFED7AA)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0xFF0F1419),
            border: Border.all(color: const Color(0x226366F1)),
            boxShadow: const [
              BoxShadow(color: Color(0x12000000), blurRadius: 16, offset: Offset(0, 4)),
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
                        Text('Slides', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                        SizedBox(height: 2),
                        Text('Carousel ya app · haraka kuscan', style: TextStyle(fontSize: 11.5, color: AdminColors.textSecondary, height: 1.3)),
                      ],
                    ),
                  ),
                  _btnPrimary(label: 'Ongeza', icon: Icons.add_rounded, small: true, onTap: () => _showSlideEditor()),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _slideMetricPill('Total', '${slides.length}', const Color(0xFF818CF8)),
                  _slideMetricPill('Active', '$activeCount', const Color(0xFF34D399)),
                  _slideMetricPill('Premium', '$premiumCount', const Color(0xFFFBBF24)),
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
              style: TextStyle(fontSize: 11, height: 1.35, color: AdminColors.textSecondary.withValues(alpha: 0.95)),
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
                Icon(Icons.photo_library_outlined, size: 28, color: Color(0xFF64748B)),
                SizedBox(height: 8),
                Text('Hakuna slide', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                SizedBox(height: 4),
                Text('Badilisha filtari au ongeza mpya', style: TextStyle(fontSize: 11, color: AdminColors.textSecondary)),
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
              return _slideListRow(s, sourceIndex, listIndex: i, showDragHandle: false);
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
        onTap: sourceIndex < 0 ? null : () => _showSlideEditor(index: sourceIndex),
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
                      child: Icon(Icons.drag_indicator_rounded, size: 22, color: AdminColors.textSecondary.withValues(alpha: 0.75)),
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
                        errorBuilder: (_, __, ___) => _slideThumbFallback(Icons.broken_image_outlined),
                      ),
                      if (!s.active)
                        Container(
                          color: const Color(0x77000000),
                          alignment: Alignment.center,
                          child: const Text('OFF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
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
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.25),
                    ),
                    if (s.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          s.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: AdminColors.textSecondary, height: 1.2),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _tinyBadge('#${s.sortOrder}', const Color(0xFF334155)),
                        _tinyBadge(s.premium ? 'PRO' : 'FREE', s.premium ? const Color(0xFFEAB308) : const Color(0xFF475569), darkText: s.premium),
                        if (!s.active) _tinyBadge('Inactive', const Color(0xFFBE123C)),
                        Text(
                          s.id,
                          style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: AdminColors.textSecondary.withValues(alpha: 0.85)),
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
                    onPressed: sourceIndex < 0 ? null : () => _showSlideEditor(index: sourceIndex),
                    icon: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF93C5FD)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0x146366F1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Futa',
                    onPressed: sourceIndex < 0 ? null : () => _confirmDeleteSlide(sourceIndex),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFFCA5A5)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0x14EF4444),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    final ordered = [..._slides]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final moved = ordered.removeAt(oldIndex);
    ordered.insert(newIdx, moved);
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].sortOrder = i + 1;
    }
    setState(() {});
    unawaited(_persistSlideSortOrders(ordered));
  }

  Future<void> _persistSlideSortOrders(List<AdminSlide> ordered) async {
    if (_adminApiKey.isEmpty) return;
    try {
      final results = await Future.wait(
        ordered.map(
          (s) => http
              .patch(
                Uri.parse('$_apiBase/api/v1/admin/slides/${s.id}'),
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
        _showToast('Mpangilio umebadilika hapa, lakini sync ya server imeshindikana.', _ToastType.warning);
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
          Container(width: 5, height: 5, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontSize: 10, color: AdminColors.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
      side: BorderSide(color: selected ? const Color(0x665B7CFA) : const Color(0x1FFFFFFF)),
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

  Future<void> _confirmDeleteSlide(int index) async {
    final s = _slides[index];
    final ok = await _showDeleteConfirmModal(
      title: 'Futa slide?',
      message: '“${s.title}” itaondolewa kwenye app moja kwa moja.',
    );
    if (ok && mounted) {
      final previousSlides = List<AdminSlide>.from(_slides);
      final deletedId = s.id;
      setState(() => _slides.removeAt(index));
      if (_adminApiKey.isNotEmpty) {
        try {
          final res = await http.delete(
            Uri.parse('$_apiBase/api/v1/admin/slides/$deletedId'),
            headers: _adminHeaders(),
          ).timeout(const Duration(seconds: 12));
          if (res.statusCode < 200 || res.statusCode >= 300) {
            throw Exception('slide delete ${res.statusCode}');
          }
          await _hydrateFromBackend();
        } catch (_) {
          if (!mounted) return;
          setState(() => _slides = previousSlides);
          _showToast('Kufuta slide kumeshindikana kwa server.', _ToastType.error);
          return;
        }
      }
      _showToast('Slide imefutwa kwenye databesi', _ToastType.success);
    }
  }

  void _showSlideEditor({int? index}) {
    final existing = index != null ? _slides[index] : null;
    final isEdit = existing != null;
    final title = TextEditingController(text: existing?.title ?? '');
    final subtitle = TextEditingController(text: existing?.subtitle ?? '');
    final imageUrl = TextEditingController(text: existing?.imageUrl ?? '');
    var premium = existing?.premium ?? false;
    var active = existing?.active ?? true;
    final sortCtl = TextEditingController(text: '${existing?.sortOrder ?? (_slides.length + 1)}');

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          backgroundColor: AdminColors.bgSecondary,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
                child: const Icon(Icons.slideshow_rounded, size: 18, color: Color(0xFFA5B4FC)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isEdit ? 'Hariri slide' : 'Slide mpya',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: -0.2),
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
                          ? _slideThumbFallback(Icons.add_photo_alternate_outlined)
                          : Image.network(
                              _safeImageUrl(imageUrl.text.trim()),
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AdminColors.accentPrimary.withValues(alpha: 0.8)),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => _slideThumbFallback(Icons.hide_image_outlined),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: title,
                    style: const TextStyle(fontSize: 13),
                    decoration: _inputDeco().copyWith(labelText: 'Kichwa', isDense: true),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: subtitle,
                    style: const TextStyle(fontSize: 13),
                    decoration: _inputDeco().copyWith(labelText: 'Subtitle', isDense: true),
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
                      decoration: _inputDeco().copyWith(labelText: 'Mpangilio', isDense: true),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ni slide ya premium', style: TextStyle(fontSize: 12.5)),
                    value: premium,
                    onChanged: (v) => setModal(() => premium = v),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Inaonekana kwenye app', style: TextStyle(fontSize: 12.5)),
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
              child: Text('Ghairi', style: TextStyle(fontSize: 13, color: AdminColors.textSecondary)),
            ),
            FilledButton(
              onPressed: () async {
                final t = title.text.trim();
                final st = subtitle.text.trim();
                final img = imageUrl.text.trim();
                final order = int.tryParse(sortCtl.text.trim()) ?? (_slides.length + 1);
                if (t.isEmpty || img.isEmpty) {
                  _showToast('Jaza title na URL ya picha', _ToastType.error);
                  return;
                }
                if (_adminApiKey.isEmpty) {
                  _showToast(
                    'WASHA_ADMIN_API_KEY haipo. Tumia admin/dev_defines.json '
                    '(ona .example) au --dart-define=WASHA_ADMIN_API_KEY=YAKO (sawa na Railway ADMIN_API_KEY).',
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
                          Uri.parse('$_apiBase/api/v1/admin/slides/$id'),
                          headers: _adminHeaders(),
                          body: jsonEncode(payloadBody),
                        )
                        .timeout(const Duration(seconds: 25));
                    if (res.statusCode < 200 || res.statusCode >= 300) {
                      throw Exception(res.body.isNotEmpty ? res.body : 'HTTP ${res.statusCode}');
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
                      throw Exception(res.body.isNotEmpty ? res.body : 'HTTP ${res.statusCode}');
                    }
                    if (!mounted) return;
                    setState(() => _slides.insert(0, newSlide));
                  }

                  if (!mounted) return;
                  Navigator.pop(ctx);
                  _showToast(
                    isEdit ? 'Slide imehifadhiwa kwenye databesi' : 'Slide imeongezwa kwenye databesi',
                    _ToastType.success,
                  );
                  unawaited(_hydrateFromBackend());
                } catch (e) {
                  if (!mounted) return;
                  _showToast('Imeshindikana kuhifadhi slide: $e', _ToastType.error);
                }
              },
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(t, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: darkText ? const Color(0xFF111827) : Colors.white)),
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
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
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

  Future<void> _confirmDeleteChannel(int index) async {
    final ch = _channels[index];
    final ok = await _showDeleteConfirmModal(
      title: 'Futa chaneli?',
      message: '“${ch.name}” itaondolewa kwenye app moja kwa moja.',
    );
    if (ok && mounted) {
      setState(() => _channels.removeAt(index));
      if (_adminApiKey.isNotEmpty) {
        try {
          await http.delete(
            Uri.parse('$_apiBase/api/v1/admin/channels/${ch.id}'),
            headers: _adminHeaders(),
          ).timeout(const Duration(seconds: 12));
        } catch (_) {}
      }
      _showToast('Chaneli imefutwa', _ToastType.error);
    }
  }

  void _showChannelEditor({int? index}) {
    final existing = index != null ? _channels[index] : null;
    final isEdit = existing != null;
    final name = TextEditingController(text: existing?.name ?? '');
    final thumb = TextEditingController(text: existing?.thumbnail ?? '');
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(isEdit ? 'Hariri chaneli' : 'Ongeza chaneli', style: const TextStyle(fontWeight: FontWeight.w800)),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Maelezo ya msingi', style: _channelFormSectionStyle()),
                    const SizedBox(height: 8),
                    TextField(
                      controller: name,
                      decoration: _inputDeco().copyWith(labelText: 'Jina la chaneli', hintText: 'mf. ESPN Ultra HD'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: category,
                      dropdownColor: AdminColors.bgSecondary,
                      decoration: _inputDeco().copyWith(labelText: 'Jamii (kama kwenye app)'),
                      items: kAppChannelCategories
                          .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) => setModal(() => category = v ?? category),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: thumb,
                      decoration: _inputDeco().copyWith(
                        labelText: 'URL ya picha (hiari)',
                        hintText: 'https://…',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Uapatikaji', style: _channelFormSectionStyle()),
                    const SizedBox(height: 6),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Chaneli hai', style: TextStyle(fontSize: 13)),
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
                      title: const Text('Mtangazo wa moja kwa moja (Live)', style: TextStyle(fontSize: 13)),
                      value: live,
                      activeThumbColor: const Color(0xFFEF4444),
                      onChanged: (v) => setModal(() => live = v ?? true),
                    ),
                    const SizedBox(height: 16),
                    Text('Ulinzi wa maudhui (DRM)', style: _channelFormSectionStyle()),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: drm,
                      dropdownColor: AdminColors.bgSecondary,
                      decoration: _inputDeco().copyWith(labelText: 'Aina ya DRM'),
                      items: const [
                        DropdownMenuItem(value: 'none', child: Text('Hakuna DRM')),
                        DropdownMenuItem(value: 'clearkey', child: Text('ClearKey')),
                        DropdownMenuItem(value: 'widevine', child: Text('Widevine')),
                      ],
                      onChanged: (v) => setModal(() => drm = v ?? 'none'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ghairi')),
              FilledButton(
                onPressed: () async {
                  final n = name.text.trim();
                  if (n.isEmpty) {
                    _showToast('Andika jina la chaneli', _ToastType.error);
                    return;
                  }
                  final tUrl = thumb.text.trim();
                  late AdminChannel syncChannel;
                  setState(() {
                    if (isEdit && index != null) {
                      final u = _channels[index];
                      u.name = n;
                      u.category = category;
                      if (tUrl.isNotEmpty) u.thumbnail = tUrl;
                      u.premium = premium;
                      u.live = live;
                      u.status = active ? 'active' : 'inactive';
                      u.drm = drm;
                      syncChannel = u;
                    } else {
                      final created = AdminChannel(
                        id: _nextChannelId(),
                        name: n,
                        category: category,
                        premium: premium,
                        live: live,
                        status: active ? 'active' : 'inactive',
                        thumbnail: tUrl.isEmpty ? 'https://picsum.photos/400/225?random=${DateTime.now().millisecondsSinceEpoch}' : tUrl,
                        viewers: 0,
                        rating: '5.0',
                        drm: drm,
                      );
                      _channels.insert(
                        0,
                        created,
                      );
                      syncChannel = created;
                    }
                  });
                  if (_adminApiKey.isNotEmpty) {
                    final payload = jsonEncode({
                      'name': syncChannel.name,
                      'category': syncChannel.category,
                      'premium': syncChannel.premium,
                      'live': syncChannel.live,
                      'status': syncChannel.status,
                      'thumbnail': syncChannel.thumbnail,
                      'viewers': syncChannel.viewers,
                      'rating': syncChannel.rating,
                      'drm': syncChannel.effectiveDrm,
                      'sort_order': 0,
                    });
                    try {
                      final res = isEdit
                          ? await http.patch(
                              Uri.parse('$_apiBase/api/v1/admin/channels/${syncChannel.id}'),
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
                    } catch (_) {
                      _showToast('Channel local saved, lakini server sync imeshindikana.', _ToastType.warning);
                    }
                  }
                  Navigator.pop(ctx);
                  _showToast(isEdit ? 'Mabadiliko yamehifadhiwa' : 'Chaneli imeongezwa', _ToastType.success);
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
  Widget _pageSubscriptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Subscriptions', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        _tableWrap(
          columns: const ['ID', 'User', 'Plan', 'Price', 'End Date', 'Status'],
          rows: _subscriptions
              .map(
                (s) => [
                  Text(s.id, style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                  Text(s.userName, style: const TextStyle(fontSize: 12)),
                  _planBadge(s.plan),
                  Text(fmtTzs(s.price), style: const TextStyle(fontSize: 12)),
                  Text(_fmtDate(s.endDate), style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
                  _badge(s.status, s.status == 'active' ? AdminColors.accentSuccess : AdminColors.accentDanger),
                ],
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _planBadge(String plan) {
    final c = plan == 'gold'
        ? AdminColors.accentWarning
        : plan == 'platinum'
            ? const Color(0xFFA78BFA)
            : const Color(0xFF60A5FA);
    return _badge(plan.toUpperCase(), c);
  }

  // --- Pricing ---
  ({String slot, IconData icon, List<Color> grad}) _planSlotMeta(String key) {
    return switch (key) {
      'weekly' => (slot: 'Wiki', icon: Icons.calendar_view_week_rounded, grad: const [Color(0xFF38BDF8), Color(0xFF2563EB)]),
      'gold' => (slot: 'Mwezi', icon: Icons.workspace_premium_rounded, grad: const [Color(0xFFFBBF24), Color(0xFFF97316)]),
      'platinum' => (slot: 'Miezi 3', icon: Icons.diamond_rounded, grad: const [Color(0xFFC084FC), Color(0xFF9333EA)]),
      _ => (slot: key, icon: Icons.sell_rounded, grad: const [Color(0xFF6366F1), Color(0xFF4F46E5)]),
    };
  }

  Widget _pagePricing() {
    const keys = ['weekly', 'gold', 'platinum'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bei za kifurushi', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text(
                    'Weka jina, bei (TSh) na muda kwa siku. Hifadhi — bei zitaonekana kwenye app ya mtumiaji.',
                    style: TextStyle(fontSize: 12, height: 1.35, color: AdminColors.textSecondary),
                  ),
                ],
              ),
            ),
            _btnOutline(label: 'Weka upya', icon: Icons.undo, onTap: _resetPricing),
            const SizedBox(width: 8),
            _btnPrimary(label: 'Hifadhi', icon: Icons.save, small: true, onTap: _savePricing),
          ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final useThree = w > 1100;
            final childW = useThree ? (w - 24) / 3 : double.infinity;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: keys.map((k) {
                return SizedBox(
                  width: childW == double.infinity ? w : childW,
                  child: _pricingPlanEditorCard(k),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _pricingPlanEditorCard(String key) {
    final p = _pricing[key]!;
    final meta = _planSlotMeta(key);
    final nameCtl = TextEditingController(text: p.name);
    return Opacity(
      opacity: p.enabled ? 1 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: p.popular ? const Color(0x55FBBF24) : const Color(0x14FFFFFF)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AdminColors.bgTertiary, AdminColors.bgSecondary.withValues(alpha: 0.65)],
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(colors: meta.grad),
                    boxShadow: [BoxShadow(color: meta.grad.first.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Icon(meta.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.slot.toUpperCase(),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AdminColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameCtl,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: 0.2),
                        decoration: _inputDeco().copyWith(labelText: 'Jina la kifurushi', hintText: 'mf. DHAHABU'),
                        onSubmitted: (v) {
                          final t = v.trim();
                          if (t.isNotEmpty) setState(() => p.name = t);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              planPeriodSubtitle(p.duration),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, c) {
                final row = c.maxWidth > 400;
                if (row) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _numField('Bei (TSh)', p.price, (v) {
                          setState(() {
                            p.price = v;
                            p.originalPrice = v;
                          });
                        }),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _intField('Muda (siku)', p.duration, (v) => setState(() => p.duration = v)),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _numField('Bei (TSh)', p.price, (v) {
                      setState(() {
                        p.price = v;
                        p.originalPrice = v;
                      });
                    }),
                    const SizedBox(height: 12),
                    _intField('Muda (siku)', p.duration, (v) => setState(() => p.duration = v)),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Inapatikana kwenye app', style: TextStyle(fontSize: 13)),
              value: p.enabled,
              activeTrackColor: const Color(0xFF6366F1),
              onChanged: (v) => setState(() => p.enabled = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _numField(String label, double value, ValueChanged<double> onChanged) {
    final c = TextEditingController(
      text: value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(2),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 12),
          decoration: _inputDeco(),
          onSubmitted: (s) {
            final v = double.tryParse(s) ?? value;
            onChanged(v);
            setState(() {});
          },
        ),
      ],
    );
  }

  Widget _intField(String label, int value, ValueChanged<int> onChanged) {
    final c = TextEditingController(text: '$value');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280))),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 12),
          decoration: _inputDeco(),
          onSubmitted: (s) {
            onChanged(int.tryParse(s) ?? value);
            setState(() {});
          },
        ),
      ],
    );
  }

  void _syncPricingDerivedFields() {
    for (final p in _pricing.values) {
      p.originalPrice = p.price;
      p.discount = 0;
    }
  }

  Future<void> _savePricing() async {
    _syncPricingDerivedFields();
    final sp = await SharedPreferences.getInstance();
    final map = {for (final e in _pricing.entries) e.key: _pricingToJson(e.value)};
    await sp.setString('washatvPricing', jsonEncode(map));

    if (_adminApiKey.isEmpty) {
      _showToast('Imehifadhiwa local pekee. Weka WASHA_ADMIN_API_KEY ili kusukuma kwenye server.', _ToastType.warning);
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
              }),
            )
            .timeout(const Duration(seconds: 12));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception('pricing ${e.key}: ${res.statusCode}');
        }
      }
      await _hydrateFromBackend();
      _showToast('Bei zimehifadhiwa. User app inasasisha moja kwa moja (sekunde 2).', _ToastType.success);
    } catch (_) {
      _showToast('Imeshindikana kuhifadhi bei kwenye server.', _ToastType.error);
    }
  }

  void _resetPricing() {
    setState(() => _pricing = defaultPricingPlans());
    SharedPreferences.getInstance().then((sp) => sp.remove('washatvPricing'));
    _showToast('Imewekwa upya', _ToastType.info);
  }

  // --- Payments ---
  Widget _pagePayments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Payments', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0x2210B981),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x3310B981)),
          ),
          child: const Text(
            'Malipo yaliyokamilika yanathibitishwa kiotomatiki. Hakuna Idhini ya msimamizi inahitajika.',
            style: TextStyle(fontSize: 11, color: AdminColors.textSecondary, height: 1.35),
          ),
        ),
        const SizedBox(height: 12),
        _tableWrap(
          columns: const ['Transaction', 'User', 'Amount', 'Status'],
          rows: _payments.take(20).map((p) {
            return [
              Text(p.transactionId, style: const TextStyle(fontSize: 11, color: AdminColors.textSecondary)),
              Text(p.userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              Text(fmtTzs(p.amount), style: const TextStyle(fontSize: 12)),
              _paymentStatusPill(p.status),
            ];
          }).toList(),
        ),
      ],
    );
  }

  // --- Notifications ---
  Widget _pageNotifications() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: Text('Notifications', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
            _btnPrimary(label: 'Send', icon: Icons.send, small: true, onTap: _modalSendNotification),
          ],
        ),
        const SizedBox(height: 12),
        ..._notifications.map((n) {
          final bg = switch (n.type) {
            'success' => const Color(0x3310B981),
            'warning' => const Color(0x33F59E0B),
            'error' => const Color(0x33EF4444),
            _ => const Color(0x336366F1),
          };
          return Opacity(
            opacity: n.read ? 0.5 : 1,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AdminColors.bgTertiary, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x0DFFFFFF))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                    child: Icon(
                      n.type == 'success' ? Icons.check : n.type == 'error' ? Icons.close : Icons.info_outline,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        Text(n.message, style: const TextStyle(fontSize: 10, color: AdminColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // --- Analytics ---
  Widget _pageAnalytics() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Analytics', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final stacked = c.maxWidth < 1024;
            final a = _chartCard('Daily Registrations', 250, _dailyRegChart());
            final b = _chartCard('Subscriptions', 250, _subDoughnut());
            if (stacked) return Column(children: [a, const SizedBox(height: 16), b]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: b)]);
          },
        ),
      ],
    );
  }

  Widget _dailyRegChart() {
    const zeroSpots = <FlSpot>[
      FlSpot(0, 0),
      FlSpot(1, 0),
      FlSpot(2, 0),
      FlSpot(3, 0),
      FlSpot(4, 0),
      FlSpot(5, 0),
      FlSpot(6, 0),
    ];
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: zeroSpots,
            isCurved: true,
            color: AdminColors.accentPrimary,
            barWidth: 2,
            belowBarData: BarAreaData(show: true, color: const Color(0x1A6366F1)),
          ),
        ],
      ),
    );
  }

  Widget _subDoughnut() {
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 44,
        sections: [
          PieChartSectionData(value: 0, color: const Color(0xFFF59E0B), title: 'Gold', radius: 48, titleStyle: const TextStyle(fontSize: 10, color: Colors.white)),
          PieChartSectionData(value: 0, color: const Color(0xFF8B5CF6), title: 'Plat', radius: 48, titleStyle: const TextStyle(fontSize: 10, color: Colors.white)),
          PieChartSectionData(value: 0, color: const Color(0xFF3B82F6), title: 'Week', radius: 48, titleStyle: const TextStyle(fontSize: 10, color: Colors.white)),
          PieChartSectionData(value: 0, color: const Color(0xFF6B7280), title: 'Free', radius: 48, titleStyle: const TextStyle(fontSize: 10, color: Colors.white)),
        ],
      ),
    );
  }

  // --- Settings ---
  Widget _pageSettings() {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: AdminColors.bgTertiary, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x0DFFFFFF))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              const Text('Site Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _settingsSiteName,
                onChanged: (v) => _settings.siteName = v,
                decoration: _inputDeco(),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Subscription Enabled', style: TextStyle(fontSize: 13)),
                value: _settings.subscriptionEnabled,
                onChanged: (v) => setState(() => _settings.subscriptionEnabled = v),
                activeThumbColor: AdminColors.accentPrimary,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Maintenance Mode', style: TextStyle(fontSize: 13)),
                value: _settings.maintenanceMode,
                onChanged: (v) => setState(() => _settings.maintenanceMode = v),
                activeThumbColor: AdminColors.accentPrimary,
              ),
              const SizedBox(height: 16),
              const Text('WhatsApp (wasiliani)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _settingsWhatsapp,
                keyboardType: TextInputType.phone,
                onChanged: (v) => _settings.whatsappNumber = v,
                decoration: _inputDeco().copyWith(
                  hintText: 'mf. +255712345678 au 0712345678',
                  prefixIcon: const Icon(Icons.chat_rounded, color: Color(0xFF22C55E), size: 20),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Nambari hii itaonekana kwenye Wasifu katika app ya mtumiaji na kutumika kuthibitisha WhatsApp.',
                style: TextStyle(fontSize: 11, height: 1.35, color: AdminColors.textSecondary),
              ),
              const SizedBox(height: 16),
              _btnPrimary(
                label: 'Hifadhi mipangilio',
                icon: Icons.save,
                onTap: () async {
                  final wa = _settingsWhatsapp.text.trim();
                  _settings.whatsappNumber = wa;
                  final sp = await SharedPreferences.getInstance();
                  await sp.setString(StorageService.supportWhatsappPrefsKey, wa);
                  if (_adminApiKey.isNotEmpty) {
                    try {
                      final res = await http
                          .patch(
                            Uri.parse('$_apiBase/api/v1/admin/settings'),
                            headers: _adminHeaders(),
                            body: jsonEncode({
                              'site_name': _settingsSiteName.text.trim(),
                              'subscription_enabled': _settings.subscriptionEnabled,
                              'maintenance_mode': _settings.maintenanceMode,
                              'whatsapp_number': wa,
                            }),
                          )
                          .timeout(const Duration(seconds: 12));
                      if (res.statusCode < 200 || res.statusCode >= 300) {
                        throw Exception('settings ${res.statusCode}');
                      }
                    } catch (_) {
                      if (!mounted) return;
                      _showToast('Imeshindikana kuhifadhi mipangilio kwenye server.', _ToastType.error);
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
    );
  }

  // --- Logs ---
  Widget _pageLogs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Activity Logs', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        _tableWrap(
          columns: const ['ID', 'Admin', 'Action', 'Date'],
          rows: _logs.take(30).map((l) {
            return [
              Text(l.id, style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
              Text(l.adminName, style: const TextStyle(fontSize: 12)),
              _badge(l.action, AdminColors.accentPrimary),
              Text(_formatLogDateTime(l.createdAt), style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
            ];
          }).toList(),
        ),
      ],
    );
  }

  Widget _tableWrap({required List<String> columns, required List<List<Widget>> rows}) {
    return Container(
      decoration: BoxDecoration(
        color: AdminColors.bgTertiary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x0DFFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Scrollbar(
            thumbVisibility: constraints.maxWidth < 640,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(AdminColors.bgSecondary),
                  headingRowHeight: 42,
                  dataRowMinHeight: 44,
                  horizontalMargin: 8,
                  columnSpacing: 10,
                  headingTextStyle: const TextStyle(color: AdminColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600),
                  columns: columns.map((c) => DataColumn(label: Text(c.toUpperCase()))).toList(),
                  rows: rows.map((cells) => DataRow(cells: cells.map((w) => DataCell(w)).toList())).toList(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pageTitleRow({required String title, required String subtitle, Widget? action}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AdminColors.textSecondary)),
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
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0x1AFFFFFF))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AdminColors.accentPrimary)),
      );

  Widget _btnPrimary({required String label, required IconData icon, required VoidCallback onTap, bool small = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 12 : 16, vertical: small ? 8 : 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: small ? 14 : 16, color: Colors.white),
            SizedBox(width: small ? 6 : 8),
            Text(label, style: TextStyle(fontSize: small ? 12 : 13, fontWeight: FontWeight.w600, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _btnOutline({required String label, required IconData icon, required VoidCallback onTap}) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AdminColors.textSecondary,
        side: const BorderSide(color: Color(0x26FFFFFF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  void _modalSendNotification() {
    final title = TextEditingController();
    final msg = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminColors.bgSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Send Notification', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: _inputDeco().copyWith(hintText: 'Title')),
            const SizedBox(height: 10),
            TextField(controller: msg, maxLines: 3, decoration: _inputDeco().copyWith(hintText: 'Message')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty || msg.text.trim().isEmpty) {
                _showToast('Fill all fields', _ToastType.error);
                return;
              }
              final newNotification = AdminNotification(
                id: 'NOT-${_notifications.length + 1}',
                title: title.text.trim(),
                message: msg.text.trim(),
                type: 'info',
                read: false,
                createdAt: DateTime.now(),
              );
              setState(() {
                _notifications.insert(0, newNotification);
              });
              if (_adminApiKey.isNotEmpty) {
                try {
                  final res = await http
                      .post(
                        Uri.parse('$_apiBase/api/v1/admin/notifications'),
                        headers: _adminHeaders(),
                        body: jsonEncode({
                          'id': newNotification.id,
                          'title': newNotification.title,
                          'message': newNotification.message,
                          'type': newNotification.type,
                          'read': false,
                        }),
                      )
                      .timeout(const Duration(seconds: 12));
                  if (res.statusCode < 200 || res.statusCode >= 300) {
                    throw Exception('notification sync ${res.statusCode}');
                  }
                } catch (_) {
                  _showToast('Notification local only, server sync failed.', _ToastType.warning);
                }
              }
              Navigator.pop(ctx);
              _showToast('Sent!', _ToastType.success);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
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
        decoration: BoxDecoration(color: const Color(0x0DFFFFFF), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0x14FFFFFF))),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: open ? const Icon(Icons.close, key: ValueKey('c'), size: 18, color: Color(0xFF94A3B8)) : const Icon(Icons.menu_rounded, key: ValueKey('m'), size: 18, color: Color(0xFF94A3B8)),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _c;
  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
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
      child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle)),
    );
  }
}
