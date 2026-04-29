import 'dart:async';
import 'dart:ui';

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

class _WashaAppState extends State<WashaApp> {
  final storage = StorageService();
  final subService = SubscriptionService();
  AppScreen current = AppScreen.home;
  String userName = '';
  String deviceId = '';
  DateTime? subEnd;
  List<Plan> userPlans = defaultUserPlans();
  Plan selectedPlan = defaultUserPlans().firstWhere((p) => p.id == 'gold', orElse: () => defaultUserPlans().first);
  String supportWhatsapp = '';
  Channel? selectedChannel;
  bool tutorialOpen = false;
  int tutorialStep = 1;
  bool pinOpen = false;
  Timer? ticker;
  int carousel = 0;

  bool get premium => subService.isPremium(subEnd);

  @override
  void initState() {
    super.initState();
    _init();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || current != AppScreen.home) return;
      setState(() => carousel = (carousel + 1) % heroSlides.length);
    });
  }

  Future<void> _init() async {
    final name = await storage.getName();
    final end = await storage.getSubscriptionEnd();
    final dev = await storage.getOrCreateDeviceId();
    final lp = await loadUserPlans();
    final wa = await storage.getSupportWhatsapp();
    if (!mounted) return;
    setState(() {
      userName = name;
      subEnd = end;
      deviceId = dev;
      userPlans = lp;
      supportWhatsapp = wa;
      selectedPlan = lp.firstWhere((p) => p.id == selectedPlan.id, orElse: () => lp.firstWhere((p) => p.id == 'gold', orElse: () => lp.first));
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
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
    await storage.setName(name);
    setState(() => pinOpen = true);
  }

  Future<void> confirmPin() async {
    subEnd = subService.calculateEndDate(selectedPlan);
    await storage.setSubscriptionEnd(subEnd);
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
        body: Stack(
          children: [
            const _OrbBackground(),
            SafeArea(
              child: Column(
                children: [
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
                    // Step-3 tutorial order: Week, Month, 3 Months.
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

  Widget _buildScreen() {
    switch (current) {
      case AppScreen.home:
        return HomeScreen(
          carouselIndex: carousel,
          onCarouselDot: (i) => setState(() => carousel = i),
          onOpenPlayer: _openPlayer,
          onOpenSubscription: () => switchScreen(AppScreen.subscription),
          premium: premium,
          displayName: userName.isEmpty ? 'Free User' : userName,
        );
      case AppScreen.player:
        return PlayerScreen(
          channel: selectedChannel,
          premium: premium,
          onBack: () => switchScreen(AppScreen.home),
          onOpenPlayer: _openPlayer,
          onOpenSubscription: () => switchScreen(AppScreen.subscription),
        );
      case AppScreen.categories:
        return CategoriesScreen(
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

const heroSlides = <HeroSlide>[
  HeroSlide(
    title: 'UEFA Champions League',
    subtitle: 'Fainali · Real Madrid vs Barcelona',
    imageUrl: 'https://images.unsplash.com/photo-1517649763962-0c623066013b?q=80&w=1470',
    premium: true,
  ),
  HeroSlide(
    title: 'Stranger Things',
    subtitle: 'Msimu 5 · Sasa Inastreami',
    imageUrl: 'https://images.unsplash.com/photo-1615986201152-7686a4867f30?q=80&w=1470',
    premium: false,
  ),
  HeroSlide(
    title: 'Dune: Unabii',
    subtitle: 'Onyesho la Kipekee',
    imageUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?q=80&w=1374',
    premium: true,
  ),
  HeroSlide(
    title: 'NBA Fainali',
    subtitle: 'Lakers vs Celtics',
    imageUrl: 'https://images.unsplash.com/photo-1504450758481-7338eba7524a?q=80&w=1469',
    premium: false,
  ),
];

const allChannels = <Channel>[
  Channel(id: 1, name: 'ESPN Ultra HD', premium: true, imageUrl: 'https://images.unsplash.com/photo-1461896836934-2e3e85baf7d9?q=80&w=1470', live: true, category: 'Sports'),
  Channel(id: 2, name: 'Sky Sports News', premium: true, imageUrl: 'https://images.unsplash.com/photo-1517649763962-0c623066013b?q=80&w=1470', live: true, category: 'Sports'),
  Channel(id: 3, name: 'Fox Sports', premium: true, imageUrl: 'https://images.unsplash.com/photo-1504450758481-7338eba7524a?q=80&w=1469', live: true, category: 'Sports'),
  Channel(id: 4, name: 'NBA TV', premium: true, imageUrl: 'https://images.unsplash.com/photo-1504450758481-7338eba7524a?q=80&w=1469', live: true, category: 'Sports'),
  Channel(id: 5, name: 'NFL Network', premium: true, imageUrl: 'https://images.unsplash.com/photo-1517649763962-0c623066013b?q=80&w=1470', live: true, category: 'Sports'),
  Channel(id: 6, name: 'HBO Max', premium: true, imageUrl: 'https://images.unsplash.com/photo-1536440136628-849c177e76a1?q=80&w=1525', live: false, category: 'Movies'),
  Channel(id: 7, name: 'Paramount Pictures', premium: true, imageUrl: 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?q=80&w=1470', live: false, category: 'Movies'),
  Channel(id: 8, name: 'Showtime', premium: true, imageUrl: 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?q=80&w=1470', live: false, category: 'Movies'),
  Channel(id: 9, name: 'Starz Cinema', premium: true, imageUrl: 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?q=80&w=1470', live: false, category: 'Movies'),
  Channel(id: 10, name: 'CNN International', premium: true, imageUrl: 'https://images.unsplash.com/photo-1585776245991-cf89dd7fc73a?q=80&w=1470', live: true, category: 'News'),
  Channel(id: 11, name: 'BBC World News', premium: true, imageUrl: 'https://images.unsplash.com/photo-1495020689067-958852a7765e?q=80&w=1469', live: true, category: 'News'),
  Channel(id: 12, name: 'Al Jazeera', premium: true, imageUrl: 'https://images.unsplash.com/photo-1495020689067-958852a7765e?q=80&w=1469', live: true, category: 'News'),
  Channel(id: 13, name: 'Trending Now', premium: true, imageUrl: 'https://images.unsplash.com/photo-1615986201152-7686a4867f30?q=80&w=1470', live: true, category: 'Trending'),
  Channel(id: 14, name: 'Viral Hits', premium: true, imageUrl: 'https://images.unsplash.com/photo-1615986201152-7686a4867f30?q=80&w=1470', live: false, category: 'Trending'),
  Channel(id: 15, name: 'Hot Topics', premium: true, imageUrl: 'https://images.unsplash.com/photo-1615986201152-7686a4867f30?q=80&w=1470', live: true, category: 'Trending'),
  Channel(id: 16, name: 'Disney Kids+', premium: true, imageUrl: 'https://images.unsplash.com/photo-1612404730960-5c71577fca11?q=80&w=1374', live: false, category: 'Kids'),
  Channel(id: 17, name: 'Nickelodeon', premium: true, imageUrl: 'https://images.unsplash.com/photo-1612404730960-5c71577fca11?q=80&w=1374', live: true, category: 'Kids'),
  Channel(id: 18, name: 'Cartoon Network', premium: true, imageUrl: 'https://images.unsplash.com/photo-1612404730960-5c71577fca11?q=80&w=1374', live: true, category: 'Kids'),
  Channel(id: 40, name: 'Movie Central', premium: false, imageUrl: 'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?q=80&w=1470', live: false, category: 'Movies'),
  Channel(id: 41, name: 'BBC News', premium: false, imageUrl: 'https://images.unsplash.com/photo-1495020689067-958852a7765e?q=80&w=1469', live: true, category: 'News'),
  Channel(id: 42, name: 'MTV Music', premium: false, imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?q=80&w=1374', live: false, category: 'Trending'),
  Channel(id: 43, name: 'Kids Fun', premium: false, imageUrl: 'https://images.unsplash.com/photo-1612404730960-5c71577fca11?q=80&w=1374', live: true, category: 'Kids'),
];
