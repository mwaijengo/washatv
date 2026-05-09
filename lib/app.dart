import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'models/channel.dart';
import 'models/hero_slide.dart';
import 'models/plan.dart';
import 'screens/categories_screen.dart';
import 'screens/home_screen.dart';
import 'screens/player_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/subscription_screen.dart';
import 'services/pricing_catalog.dart';
import 'services/public_api_service.dart';
import 'services/storage_service.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';
import 'widgets/bottom_nav.dart';

enum AppScreen { home, player, categories, profile, subscription }

class WashaApp extends StatefulWidget {
  const WashaApp({super.key});

  @override
  State<WashaApp> createState() => _WashaAppState();
}

class _WashaAppState extends State<WashaApp> with WidgetsBindingObserver {
  final storage = StorageService();
  final subService = SubscriptionService();
  final api = PublicApiService();
  AppScreen current = AppScreen.home;
  String userName = '';
  String pendingPhone = '';
  String deviceId = '';
  DateTime? subEnd;
  List<Plan> userPlans = defaultUserPlans();
  List<Channel> channels = const <Channel>[];
  List<HeroSlide> slides = const <HeroSlide>[];
  Plan selectedPlan = defaultUserPlans().firstWhere((p) => p.id == 'gold', orElse: () => defaultUserPlans().first);
  String supportWhatsapp = '';
  bool bootLoading = true;
  Channel? selectedChannel;
  bool tutorialOpen = false;
  int tutorialStep = 1;
  bool pinOpen = false;
  int remoteConfigVersion = 0;
  bool syncInFlight = false;
  String? bootstrapError;
  /// Last exception from bootstrap (debug/profile only — shown in banner to diagnose emulator/network).
  String? bootstrapFailureDetail;
  Timer? ticker;
  Timer? carouselTimer;
  Timer? configPoller;
  int carousel = 0;

  bool get premium => subService.isPremium(subEnd);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || current != AppScreen.home) return;
      if (slides.isEmpty) return;
      setState(() => carousel = (carousel + 1) % slides.length);
    });
    configPoller = Timer.periodic(const Duration(seconds: 5), (_) => _syncFromServer(silent: true));
  }

  Future<void> _init() async {
    final name = await storage.getName();
    final end = await storage.getSubscriptionEnd();
    final dev = await storage.getOrCreateDeviceId();
    final localPlans = await loadUserPlans();
    final localWa = await storage.getSupportWhatsapp();
    var fetchedPlans = localPlans;
    var fetchedChannels = <Channel>[];
    var fetchedSlides = const <HeroSlide>[];
    var fetchedWa = localWa;
    String? fetchErr;
    String? lastFailure;

    var remoteFetched = false;
    for (var attempt = 0; attempt < 5 && !remoteFetched; attempt++) {
      try {
        final remote = await api.fetchBootstrap();
        remoteConfigVersion = remote.version;
        fetchedPlans = remote.plans.isNotEmpty ? remote.plans : defaultUserPlans();
        fetchedChannels = remote.channels;
        fetchedSlides = remote.slides;
        fetchedWa = remote.whatsappNumber;
        // Mark success before local prefs — SharedPreferences can fail on web (private mode,
        // blocked storage) and must not look like a dead API / CORS issue.
        remoteFetched = true;
        lastFailure = null;
        try {
          await storage.setSupportWhatsapp(fetchedWa);
        } catch (_) {}
        try {
          await api.syncViewer(
            deviceId: dev,
            name: name.isEmpty ? 'Free User' : name,
          );
        } catch (_) {
          // Non-blocking: app can continue even if user sync endpoint is not ready.
        }
      } catch (e, st) {
        final msg = e.toString();
        lastFailure = msg.length > 400 ? '${msg.substring(0, 400)}…' : msg;
        debugPrint('WASHA bootstrap attempt ${attempt + 1}/5 failed: $e\n$st');
        if (attempt < 4) {
          await Future<void>.delayed(Duration(seconds: 1 + attempt));
        }
      }
    }
    if (!remoteFetched) {
      fetchErr = kIsWeb
          ? 'Chrome haipatikani data kutoka seva (CORS, URL isiyo sahihi, au seva imezima). '
              'Angalia URL hapa chini; jaribu kubofya Jaribu tena.'
          : 'Hatukuunganisha na seva ya WASHA. Angalia mtandao, URL ya API, au seva iko wazi.';
    }

    if (!mounted) return;
    setState(() {
      userName = name;
      subEnd = end;
      deviceId = dev;
      userPlans = fetchedPlans;
      channels = fetchedChannels;
      slides = fetchedSlides;
      supportWhatsapp = fetchedWa;
      bootstrapError = fetchErr;
      bootstrapFailureDetail = fetchErr != null ? lastFailure : null;
      selectedPlan = fetchedPlans.firstWhere((p) => p.id == selectedPlan.id, orElse: () => fetchedPlans.firstWhere((p) => p.id == 'gold', orElse: () => fetchedPlans.first));
      bootLoading = false;
    });
  }

  Future<void> _syncFromServer({bool silent = false}) async {
    if (syncInFlight) return;
    syncInFlight = true;
    try {
      final latest = await api.fetchConfigVersion();
      if (latest <= remoteConfigVersion) return;
      final remote = await api.fetchBootstrap();
      if (!mounted) return;
      setState(() {
        remoteConfigVersion = remote.version;
        userPlans = remote.plans.isNotEmpty ? remote.plans : defaultUserPlans();
        channels = remote.channels;
        slides = remote.slides;
        if (carousel >= slides.length) carousel = 0;
        supportWhatsapp = remote.whatsappNumber;
        bootstrapError = null;
        bootstrapFailureDetail = null;
        if (userPlans.isNotEmpty) {
          selectedPlan = userPlans.firstWhere(
            (p) => p.id == selectedPlan.id,
            orElse: () => userPlans.first,
          );
        }
      });
      await storage.setSupportWhatsapp(remote.whatsappNumber);
    } catch (_) {
      if (!silent && mounted) {
        setState(() {
          bootstrapError = 'Imeshindikana kusasisha data. Jaribu tena.';
        });
      }
    } finally {
      syncInFlight = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncFromServer(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    carouselTimer?.cancel();
    configPoller?.cancel();
    super.dispose();
  }

  void switchScreen(AppScreen s) {
    setState(() => current = s);
    if (s == AppScreen.subscription && !premium) {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        setState(() {
          tutorialOpen = true;
          tutorialStep = 1;
        });
      });
    }
  }

  Future<void> activateSubscription(String phone, String name) async {
    userName = name;
    pendingPhone = phone;
    await storage.setName(name);
    setState(() => pinOpen = true);
  }

  Future<void> confirmPin() async {
    subEnd = subService.calculateEndDate(selectedPlan);
    await storage.setSubscriptionEnd(subEnd);
    try {
      await api.recordCompletedTransaction(
        deviceId: deviceId,
        userName: userName.isEmpty ? 'Free User' : userName,
        phone: pendingPhone,
        amount: _planAmount(selectedPlan),
        method: 'M-Pesa',
        planKey: selectedPlan.id,
      );
      await api.syncViewer(
        deviceId: deviceId,
        name: userName.isEmpty ? 'Free User' : userName,
        phone: pendingPhone,
      );
      await _syncFromServer(silent: true);
    } catch (_) {
      // Keep local access even if network blips; server sync will retry on poll.
    }
    setState(() {
      pinOpen = false;
    });
  }

  Future<void> cancelSubscription() async {
    await storage.setSubscriptionEnd(null);
    setState(() => subEnd = null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WASHA TV',
      theme: AppTheme.build(),
      home: Scaffold(
        body: bootLoading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  const _OrbBackground(),
                  SafeArea(
                    child: Column(
                      children: [
                        if (bootstrapError != null) _bootstrapErrorBanner(),
                        Expanded(child: _buildScreen()),
                        if (current != AppScreen.player)
                          BottomNav(
                            current: current,
                            onTap: switchScreen,
                          ),
                      ],
                    ),
                  ),
                  if (tutorialOpen)
                    SubscriptionScreen.buildTutorialModal(
                      step: tutorialStep,
                      onClose: () => setState(() => tutorialOpen = false),
                      onNext: () => setState(() => tutorialStep = (tutorialStep + 1).clamp(1, 5)),
                      onBack: () => setState(() => tutorialStep = (tutorialStep - 1).clamp(1, 5)),
                      onFinish: () => setState(() => tutorialOpen = false),
                      onHighlightedOptionChanged: (index) {
                        setState(() {
                          selectedPlan = switch (index) {
                            0 => userPlans.firstWhere((p) => p.id == 'weekly', orElse: () => userPlans.first),
                            1 => userPlans.firstWhere((p) => p.id == 'gold', orElse: () => userPlans.first),
                            _ => userPlans.firstWhere((p) => p.id == 'platinum', orElse: () => userPlans.first),
                          };
                        });
                      },
                    ),
                  if (pinOpen)
                    SubscriptionScreen.buildPinModal(
                      onCancel: () => setState(() => pinOpen = false),
                      onConfirm: confirmPin,
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _retryBootstrapAfterError() async {
    setState(() {
      bootstrapError = null;
      bootstrapFailureDetail = null;
      bootLoading = true;
    });
    await _init();
  }

  Widget _bootstrapErrorBanner() {
    final msg = bootstrapError!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xE9181820),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x55FBBF24)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.cloud_off_rounded, color: Color(0xFFFBBF24), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Seva haipatikani', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 5),
                    Text(msg, style: const TextStyle(fontSize: 12, height: 1.35, color: Color(0xFFCBD5E1))),
                    const SizedBox(height: 10),
                    const Text(
                      'URL inayotumiwa:',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      api.baseUrl,
                      style: const TextStyle(fontSize: 11.5, height: 1.35, color: Color(0xFFE2E8F0), fontFamily: 'monospace'),
                    ),
                    if (!kReleaseMode && bootstrapFailureDetail != null) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Kiini cha makosa (debug):',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        bootstrapFailureDetail!,
                        style: const TextStyle(fontSize: 10, height: 1.35, color: Color(0xFF94A3B8), fontFamily: 'monospace'),
                      ),
                    ],
                    if (!kIsWeb && !kReleaseMode) ...[
                      const SizedBox(height: 8),
                      Text(
                        api.baseUrl.startsWith('http://')
                            ? 'Android: HTTP inatumika — manifest inaruhusu cleartext. Kwa API kwenye kompyuta tumia http://10.0.2.2:PORT kwenye emulator.'
                            : 'Android emulator: hakikisha intaneti inafanya; jaribu browser ndani ya emulator kwenye URL ya /health ya seva.',
                        style: const TextStyle(fontSize: 10, height: 1.4, color: Color(0xFF94A3B8)),
                      ),
                    ],
                    if (kIsWeb) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Kurekebisha: fungua terminal na endesha app na\n'
                        '--dart-define=WASHA_API_BASE_URL=URL_YA_SEVE_YAKO\n'
                        'mfano kwa seva ndogo ndani ya kompyuta: http://127.0.0.1:8080',
                        style: TextStyle(fontSize: 10, height: 1.4, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.tonal(
                onPressed: _retryBootstrapAfterError,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('Jaribu tena'),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF9CA3AF)),
                tooltip: 'Ficha',
                onPressed: () => setState(() {
                  bootstrapError = null;
                  bootstrapFailureDetail = null;
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _planAmount(Plan p) {
    final digits = p.price.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(digits) ?? 0;
  }

  Widget _buildScreen() {
    switch (current) {
      case AppScreen.home:
        return HomeScreen(
          channels: channels,
          slides: slides,
          carouselConfigVersion: remoteConfigVersion,
          carouselIndex: carousel,
          onCarouselDot: (i) => setState(() => carousel = i),
          onOpenPlayer: _openPlayer,
          onOpenSubscription: () => switchScreen(AppScreen.subscription),
          premium: premium,
          displayName: userName.isEmpty ? 'Free User' : userName,
        );
      case AppScreen.player:
        return PlayerScreen(
          channels: channels,
          channel: selectedChannel,
          premium: premium,
          onBack: () => switchScreen(AppScreen.home),
          onOpenPlayer: _openPlayer,
          onOpenSubscription: () => switchScreen(AppScreen.subscription),
        );
      case AppScreen.categories:
        return CategoriesScreen(
          channels: channels,
          premium: premium,
          onOpenPlayer: _openPlayer,
          onOpenSubscription: () => switchScreen(AppScreen.subscription),
        );
      case AppScreen.profile:
        return ProfileScreen(
          premium: premium,
          userName: userName.isEmpty ? 'Free User' : userName,
          deviceId: deviceId,
          endDate: subEnd,
          selectedPlan: selectedPlan,
          supportWhatsapp: supportWhatsapp,
          onCancel: cancelSubscription,
          onOpenSubscription: () => switchScreen(AppScreen.subscription),
        );
      case AppScreen.subscription:
        return SubscriptionScreen(
          plans: userPlans,
          premium: premium,
          selectedPlan: selectedPlan,
          onPlanChange: (p) => setState(() => selectedPlan = p),
          onPay: activateSubscription,
          onOpenTutorial: () => setState(() {
            tutorialStep = 1;
            tutorialOpen = true;
          }),
        );
    }
  }

  void _openPlayer(Channel c) {
    if (c.premium && !premium) {
      switchScreen(AppScreen.subscription);
      return;
    }
    setState(() {
      selectedChannel = c;
      current = AppScreen.player;
    });
  }
}

class _OrbBackground extends StatelessWidget {
  const _OrbBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.5,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
            child: Stack(
              children: const [
                _Orb(size: 420, left: 40, top: 120, colors: [Color(0x4D6366F1), Color(0x0FA855F7)]),
                _Orb(size: 380, left: 220, top: 90, colors: [Color(0x40EC4899), Color(0x0FEF4444)]),
                _Orb(size: 300, left: 10, top: 540, colors: [Color(0x384ECDC4), Color(0x0F38BDF8)]),
                _Orb(size: 340, left: 180, top: 620, colors: [Color(0x38FB923C), Color(0x0FFACC15)]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Orb extends StatefulWidget {
  const _Orb({
    required this.size,
    required this.left,
    required this.top,
    required this.colors,
  });

  final double size;
  final double left;
  final double top;
  final List<Color> colors;

  @override
  State<_Orb> createState() => _OrbState();
}

class _OrbState extends State<_Orb> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat(reverse: true);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.left,
      top: widget.top,
      child: AnimatedBuilder(
        animation: c,
        builder: (_, __) {
          final t = c.value;
          return Transform.translate(
            offset: Offset(30 - 50 * t, -45 + 80 * t),
            child: Transform.scale(
              scale: 1 + (t - 0.5) * 0.12,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.2, -0.2),
                    colors: widget.colors,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

