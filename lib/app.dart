import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/app_update_status.dart';
import 'models/channel.dart';
import 'models/hero_slide.dart';
import 'models/plan.dart';
import 'models/viewer_profile.dart';
import 'screens/categories_screen.dart';
import 'screens/force_update_screen.dart';
import 'screens/home_screen.dart';
import 'screens/player_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/subscription_screen.dart';
import 'services/app_identity.dart';
import 'services/pricing_catalog.dart';
import 'services/public_api_service.dart';
import 'services/push_notification_service.dart';
import 'services/payment_config.dart';
import 'services/secure_playback_client.dart';
import 'services/sonicpesa_payment_service.dart';
import 'screens/settings_screen.dart';
import 'services/app_cache_service.dart';
import 'services/app_settings_service.dart';
import 'services/native_android_player.dart';
import 'services/storage_service.dart';
import 'services/subscription_service.dart';
import 'theme/app_theme.dart';
import 'utils/player_orientation.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/cinematic_background.dart';
import 'widgets/no_internet_modal.dart';
import 'widgets/notification_permission_dialog.dart';

enum AppScreen { home, player, categories, profile, subscription, settings }

const _secureChannel = MethodChannel('com.washatv/secure');

Future<void> _enableScreenSecurity() async {
  if (kIsWeb) return;
  try {
    await _secureChannel.invokeMethod('setSecure', {'secure': true});
  } catch (_) {}
}

class WashaApp extends StatefulWidget {
  const WashaApp({super.key});

  @override
  State<WashaApp> createState() => _WashaAppState();
}

class _WashaAppState extends State<WashaApp> with WidgetsBindingObserver {
  final storage = StorageService();
  final subService = SubscriptionService();
  final api = PublicApiService();
  final sonicPay = SonicpesaPaymentService();
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
  bool paymentOverlayOpen = false;
  SonicpesaPaymentPhase paymentPhase = SonicpesaPaymentPhase.idle;
  String? paymentOrderId;
  String? paymentError;
  String? paymentStatusLine;
  bool subscriptionPaymentSuccess = false;
  String? _paymentRetryPhone;
  String? _paymentRetryName;
  /// When false, "Jaribu tena" resumes the existing order instead of creating a new STK push.
  bool _paymentAllowNewCharge = true;
  DateTime? _paymentCooldownUntil;
  /// After a successful payment, keep local unlock briefly while the server profile catches up.
  DateTime? _paymentUnlockGraceUntil;
  int remoteConfigVersion = 0;
  int remoteConfigSyncedAt = 0;
  String? bootstrapSyncSignature;
  bool subscriptionEnabled = true;
  bool maintenanceMode = false;
  AppUpdateStatus appUpdate = AppUpdateStatus.empty;
  String siteName = 'WASHA TV';
  bool syncInFlight = false;
  bool metaPollInFlight = false;
  bool syncRefreshing = false;
  bool pendingConfigSync = false;
  int configPollTick = 0;
  String? bootstrapError;
  /// Last exception from bootstrap (debug/profile only — shown in banner to diagnose emulator/network).
  String? bootstrapFailureDetail;
  bool _noInternetVisible = false;
  bool _noInternetRetrying = false;
  Timer? _premiumExpiryTimer;
  Timer? carouselTimer;
  Timer? configPoller;
  int carousel = 0;
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  AppScreen _returnScreen = AppScreen.home;
  PlayerBackHandler? _playerBackHandler;
  bool _playerFullscreen = false;
  DateTime? _lastExitBackPress;
  String _premiumPlanLabel = '';
  String _premiumAccessSource = 'none';
  int _imageCacheBust = 0;

  int get _effectiveImageCacheEpoch => remoteConfigVersion + _imageCacheBust;

  bool get premium => subService.isPremium(subEnd);

  String get _displayName {
    final n = userName.trim();
    if (n.isEmpty || isGenericViewerName(n)) return 'Mtumiaji';
    return n;
  }

  void _lockShellPortrait() {
    if (_playerFullscreen) return;
    unawaited(PlayerOrientation.lockHomePortrait());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockShellPortrait();
    unawaited(_enableScreenSecurity());
    unawaited(AppSettingsService.instance.load());
    _init();
    _schedulePremiumExpiryCheck();
    carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || current != AppScreen.home) return;
      if (slides.isEmpty) return;
      setState(() => carousel = (carousel + 1) % slides.length);
    });
    // Live sync: meta poll every 8s (paused while player is open).
    _startConfigPoller();
  }

  void _startConfigPoller() {
    configPoller?.cancel();
    configPoller = Timer.periodic(const Duration(seconds: 8), (_) => _pollConfigMeta());
  }

  void _pauseConfigPoller() {
    configPoller?.cancel();
    configPoller = null;
  }

  /// One-shot timer when premium expires — avoids rebuilding the whole app every second.
  void _schedulePremiumExpiryCheck() {
    _premiumExpiryTimer?.cancel();
    final end = subEnd;
    if (end == null) return;
    final now = DateTime.now();
    if (!end.isAfter(now)) {
      if (mounted) setState(() {});
      return;
    }
    final wait = end.difference(now) + const Duration(seconds: 1);
    _premiumExpiryTimer = Timer(wait, () {
      if (!mounted) return;
      setState(() {});
      _schedulePremiumExpiryCheck();
    });
  }

  void _startLiveSyncAfterBoot() {
    if (!mounted || bootLoading) return;
    if (appUpdate.updateRequired) return;
    unawaited(_pollConfigMeta());
    unawaited(_syncViewerProfileFromServer());
    unawaited(_syncPushTopics());
    unawaited(_recoverPendingPayment(silent: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || bootLoading || appUpdate.updateRequired) return;
      unawaited(
        maybeShowWashaNotificationPermissionDialog(
          context,
          deviceId: deviceId,
          isPremium: premium,
        ),
      );
    });
  }

  Future<void> _syncPushTopics() async {
    if (deviceId.isEmpty) return;
    try {
      await PushNotificationService.ensureRegistered(
        deviceId: deviceId,
        isPremium: premium,
        api: api,
      );
    } catch (e, st) {
      debugPrint('Washa push topics: $e\n$st');
    }
  }

  Future<void> _init() async {
    await AppIdentity.ensureLoaded();
    var name = await storage.getName();
    var subEndLocal = await storage.getSubscriptionEnd();
    final dev = await storage.ensureDeviceIdPersisted();
    final localPlans = await loadUserPlans();
    final localWa = await storage.getSupportWhatsapp();
    var fetchedPlans = localPlans;
    var fetchedChannels = <Channel>[];
    var fetchedSlides = const <HeroSlide>[];
    var fetchedWa = localWa;
    var fetchedSubscriptionEnabled = true;
    var fetchedMaintenanceMode = false;
    var fetchedSiteName = 'WASHA TV';
    var fetchedAppUpdate = AppUpdateStatus.empty.copyWith(
      currentVersion: AppIdentity.version,
      currentBuild: AppIdentity.build,
    );
    String? fetchErr;
    String? lastFailure;

    bootstrapSyncSignature = await api.loadBootstrapSyncSignature();
    var remoteFetched = false;
    for (var attempt = 0; attempt < 5 && !remoteFetched; attempt++) {
      try {
        final remote = await api.fetchBootstrap();
        remoteConfigVersion = _safeConfigVersion(remote.version);
        remoteConfigSyncedAt = remote.configSyncedAt is int && remote.configSyncedAt >= 0
            ? remote.configSyncedAt
            : 0;
        bootstrapSyncSignature = remote.syncSignature;
        fetchedSubscriptionEnabled = remote.subscriptionEnabled;
        fetchedMaintenanceMode = remote.maintenanceMode;
        fetchedSiteName = remote.siteName;
        fetchedAppUpdate = remote.appUpdate;
        var remotePlans = remote.plans;
        if (remotePlans.isEmpty) {
          try {
            remotePlans = await api.fetchPublicPlans();
          } catch (e, st) {
            debugPrint('WASHA fetchPublicPlans fallback: $e\n$st');
          }
        }
        fetchedPlans = remotePlans.isNotEmpty ? remotePlans : localPlans;
        fetchedChannels = remote.channels;
        fetchedSlides = remote.slides;
        fetchedWa = remote.whatsappNumber;
        // Mark success before local prefs — SharedPreferences can fail on web (private mode,
        // blocked storage) and must not look like a dead API / CORS issue.
        remoteFetched = true;
        lastFailure = null;
        api.resetLightweightPollBackoff();
        try {
          await storage.setSupportWhatsapp(fetchedWa);
        } catch (_) {}
        if (fetchedPlans.isNotEmpty) {
          await persistPricingSnapshotFromPlans(fetchedPlans);
        }
        try {
          // Always register device in admin users table — retry so transient failures
          // do not leave viewers invisible to admins.
          var synced = false;
          for (var syncAttempt = 0; syncAttempt < 3 && !synced; syncAttempt++) {
            try {
              await api.syncViewer(deviceId: dev, name: name.isEmpty ? null : name);
              synced = true;
            } catch (e) {
              debugPrint('WASHA users/sync attempt ${syncAttempt + 1}/3: $e');
              if (syncAttempt < 2) {
                await Future<void>.delayed(Duration(milliseconds: 400 * (syncAttempt + 1)));
              }
            }
          }
          final profile = await api.fetchViewerProfile(dev);
          if (profile != null) {
            if (!isGenericViewerName(profile.name)) {
              name = profile.name.trim();
              await storage.setName(name);
            }
            final serverEnd = profile.premiumActive ? profile.premiumUntil : null;
            // Trust server after profile sync so revoke/expiry clears local unlocks.
            subEndLocal = subService.mergeEndDates(subEndLocal, serverEnd, preferRemote: true);
            await storage.setSubscriptionEnd(subEndLocal);
            _premiumPlanLabel = profile.planName ?? profile.planKey ?? '';
            _premiumAccessSource = profile.accessSource;
          }
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
      final cached = await api.loadBootstrapCache();
      if (cached != null) {
        remoteFetched = true;
        remoteConfigVersion = cached.version;
        remoteConfigSyncedAt = cached.configSyncedAt;
        bootstrapSyncSignature = cached.syncSignature;
        fetchedPlans = cached.plans.isNotEmpty ? cached.plans : localPlans;
        fetchedChannels = cached.channels;
        fetchedSlides = cached.slides;
        fetchedWa = cached.whatsappNumber.isNotEmpty ? cached.whatsappNumber : localWa;
        fetchedSubscriptionEnabled = cached.subscriptionEnabled;
        fetchedMaintenanceMode = cached.maintenanceMode;
        fetchedSiteName = cached.siteName;
        fetchedAppUpdate = cached.appUpdate;
        fetchErr = null;
        lastFailure = null;
        // Still register this device for admin even when catalog came from cache.
        try {
          await api.syncViewer(deviceId: dev, name: name.isEmpty ? null : name);
        } catch (_) {}
      } else {
        fetchErr = kIsWeb
            ? 'Chrome haipatikani data kutoka seva (CORS, URL isiyo sahihi, au seva imezima). '
                'Angalia URL hapa chini; jaribu kubofya Jaribu tena.'
            : 'Hatukuunganisha na seva ya WASHA. Angalia mtandao, URL ya API, au seva iko wazi.';
      }
    }

    if (!mounted) return;
    setState(() {
      userName = name;
      subEnd = subEndLocal;
      deviceId = dev;
      userPlans = fetchedPlans;
      channels = fetchedChannels;
      slides = fetchedSlides;
      supportWhatsapp = fetchedWa;
      subscriptionEnabled = fetchedSubscriptionEnabled;
      maintenanceMode = fetchedMaintenanceMode;
      appUpdate = fetchedAppUpdate;
      siteName = fetchedSiteName;
      bootstrapError = fetchErr;
      bootstrapFailureDetail = fetchErr != null ? lastFailure : null;
      selectedPlan = fetchedPlans.isNotEmpty
          ? fetchedPlans.firstWhere(
              (p) => p.id == selectedPlan.id,
              orElse: () => fetchedPlans.firstWhere((p) => p.id == 'gold', orElse: () => fetchedPlans.first),
            )
          : selectedPlan;
      bootLoading = false;
      // Show no-internet modal only when all retries failed AND no cached data.
      _noInternetVisible = fetchErr != null && !kIsWeb;
      _noInternetRetrying = false;
    });
    _schedulePremiumExpiryCheck();
    _startLiveSyncAfterBoot();
  }

  int _safePollTick() {
    final t = configPollTick;
    if (t is! int || t < 0) return 0;
    return t;
  }

  void _bumpConfigPollTick() {
    configPollTick = _safePollTick() + 1;
  }

  int _safeConfigVersion(int v) {
    if (v is! int || v < 0) return 0;
    return v;
  }

  Future<void> _pollConfigMeta() async {
    if (bootLoading || metaPollInFlight || api.shouldSkipLightweightPoll) return;
    if (current == AppScreen.player) return;
    metaPollInFlight = true;
    try {
      _bumpConfigPollTick();
      final tick = configPollTick;
      final changedSig = await api.fetchBootstrapMetaIfChanged(
        bootstrapSyncSignature,
        localVersion: _safeConfigVersion(remoteConfigVersion),
      );
      if (changedSig != null) {
        if (syncInFlight) {
          pendingConfigSync = true;
        } else {
          await _syncFromServer(silent: true, forceFull: true);
        }
      } else if (tick % 4 == 0 && !syncInFlight && !api.shouldSkipLightweightPoll) {
        await _syncFromServer(silent: true);
      }
      // Profile poll ~every 32s during background sync; screen switches still refresh immediately.
      if (tick % 4 == 0 && !api.shouldSkipLightweightPoll) {
        unawaited(_syncViewerProfileFromServer());
      }
    } finally {
      metaPollInFlight = false;
      if (pendingConfigSync && !syncInFlight && !bootLoading) {
        pendingConfigSync = false;
        unawaited(_syncFromServer(silent: true, forceFull: true));
      }
    }
  }

  Future<void> _syncViewerProfileFromServer() async {
    if (deviceId.isEmpty || api.shouldSkipLightweightPoll) return;
    try {
      await api.syncViewer(
        deviceId: deviceId,
        name: isGenericViewerName(userName) ? null : userName,
        phone: pendingPhone.trim().isEmpty ? null : pendingPhone,
      );
      final profile = await api.fetchViewerProfile(deviceId);
      if (!mounted || profile == null) return;
      _applyViewerProfile(profile);
    } catch (_) {}
  }

  void _applyViewerProfile(ViewerProfile profile) {
    final wasPremium = premium;
    final serverEnd = profile.premiumActive ? profile.premiumUntil : null;
    final inPaymentGrace = _paymentUnlockGraceUntil != null &&
        DateTime.now().isBefore(_paymentUnlockGraceUntil!) &&
        subService.isPremium(subEnd);

    // Server is authoritative for revoke/expiry, but never wipe a fresh paid unlock
    // on a brief free profile read before reconcile finishes.
    final DateTime? nextEnd;
    if (profile.premiumActive && serverEnd != null) {
      nextEnd = subService.mergeEndDates(subEnd, serverEnd);
      if (subService.isPremium(serverEnd)) {
        _paymentUnlockGraceUntil = null;
      }
    } else if (inPaymentGrace) {
      nextEnd = subEnd;
    } else {
      nextEnd = subService.mergeEndDates(subEnd, serverEnd, preferRemote: true);
    }

    Plan nextPlan = selectedPlan;
    final key = profile.planKey?.trim();
    if (key != null && key.isNotEmpty) {
      for (final p in userPlans) {
        if (p.id == key) {
          nextPlan = p;
          break;
        }
      }
    }

    final nextName = isGenericViewerName(profile.name) ? userName : profile.name.trim();
    final label = (profile.planName?.trim().isNotEmpty == true)
        ? profile.planName!.trim()
        : (key != null && key.isNotEmpty ? nextPlan.name : '');

    if (current == AppScreen.player) {
      if (!isGenericViewerName(profile.name)) userName = nextName;
      subEnd = nextEnd;
      selectedPlan = nextPlan;
      _premiumPlanLabel = label;
      _premiumAccessSource = profile.accessSource;
      if (!isGenericViewerName(profile.name)) {
        unawaited(storage.setName(userName));
      }
      unawaited(storage.setSubscriptionEnd(nextEnd));
      if (wasPremium != premium) unawaited(_syncPushTopics());
      _schedulePremiumExpiryCheck();
      return;
    }

    setState(() {
      if (!isGenericViewerName(profile.name)) userName = nextName;
      subEnd = nextEnd;
      selectedPlan = nextPlan;
      _premiumPlanLabel = label;
      _premiumAccessSource = profile.accessSource;
    });

    if (!isGenericViewerName(profile.name)) {
      unawaited(storage.setName(userName));
    }
    unawaited(storage.setSubscriptionEnd(nextEnd));
    if (wasPremium != premium) {
      unawaited(_syncPushTopics());
    }
    _schedulePremiumExpiryCheck();
  }

  Future<void> _syncFromServer({bool silent = false, bool forceFull = false}) async {
    if (bootLoading) return;
    if (current == AppScreen.player && silent && !forceFull) return;
    if (syncInFlight) {
      if (forceFull) pendingConfigSync = true;
      return;
    }
    syncInFlight = true;
    if (silent && mounted) setState(() => syncRefreshing = true);
    try {
      final PublicBootstrapData? remote = forceFull
          ? await api.fetchBootstrap()
          : await api.fetchBootstrapSince(remoteConfigVersion);
      if (remote == null) {
        await _syncViewerProfileFromServer();
        return;
      }
      if (!mounted) return;
      var remotePlans = remote.plans;
      if (remotePlans.isEmpty) {
        try {
          remotePlans = await api.fetchPublicPlans();
        } catch (_) {}
      }
      final nextPlans = remotePlans.isNotEmpty ? remotePlans : await loadUserPlans();
      setState(() {
        remoteConfigVersion = _safeConfigVersion(remote.version);
        remoteConfigSyncedAt = remote.configSyncedAt is int && remote.configSyncedAt >= 0
            ? remote.configSyncedAt
            : 0;
        bootstrapSyncSignature = remote.syncSignature;
        subscriptionEnabled = remote.subscriptionEnabled;
        maintenanceMode = remote.maintenanceMode;
        appUpdate = remote.appUpdate;
        siteName = remote.siteName;
        userPlans = nextPlans;
        channels = remote.channels;
        slides = remote.slides;
        if (carousel >= slides.length) carousel = 0;
        supportWhatsapp = remote.whatsappNumber;
        bootstrapError = null;
        bootstrapFailureDetail = null;
        selectedPlan = userPlans.isNotEmpty
            ? userPlans.firstWhere(
                (p) => p.id == selectedPlan.id,
                orElse: () => userPlans.firstWhere((p) => p.id == 'gold', orElse: () => userPlans.first),
              )
            : selectedPlan;
      });
      api.resetLightweightPollBackoff();
      await storage.setSupportWhatsapp(remote.whatsappNumber);
      if (nextPlans.isNotEmpty) {
        await persistPricingSnapshotFromPlans(nextPlans);
      }
      await _syncViewerProfileFromServer();
    } catch (_) {
      if (!silent && mounted) {
        setState(() {
          bootstrapError = 'Imeshindikana kusasisha data. Jaribu tena.';
        });
      }
    } finally {
      syncInFlight = false;
      if (mounted && syncRefreshing) {
        setState(() => syncRefreshing = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lockShellPortrait();
      unawaited(_enableScreenSecurity());
      unawaited(_reconcileDeviceIdFromStorage());
      if (current != AppScreen.player) {
        unawaited(_syncFromServer(silent: true, forceFull: true));
      }
      unawaited(_syncViewerProfileFromServer());
      unawaited(_recoverPendingPayment(silent: true));
    }
  }

  /// Keeps the same device id after app updates / OS restore (never rotate silently).
  Future<void> _reconcileDeviceIdFromStorage() async {
    final id = await storage.ensureDeviceIdPersisted();
    if (!mounted || id.isEmpty) return;
    if (id != deviceId) setState(() => deviceId = id);
    unawaited(_syncPushTopics());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _premiumExpiryTimer?.cancel();
    carouselTimer?.cancel();
    configPoller?.cancel();
    super.dispose();
  }

  void switchScreen(AppScreen s) {
    setState(() {
      current = s;
      if (s != AppScreen.player) {
        selectedChannel = null;
        _playerBackHandler = null;
        _playerFullscreen = false;
        _startConfigPoller();
      }
    });
    _lockShellPortrait();
    unawaited(_pollConfigMeta());
    if (s == AppScreen.subscription) {
      unawaited(_syncFromServer(silent: true, forceFull: true));
    }
    if (s == AppScreen.subscription || s == AppScreen.profile || s == AppScreen.settings) {
      unawaited(_syncViewerProfileFromServer());
    }
  }

  void _leavePlayer() {
    switchScreen(_returnScreen);
  }

  Future<Channel?> _resolveChannelStream(Channel channel) async {
    try {
      final id = deviceId.isNotEmpty ? deviceId : await storage.getOrCreateDeviceId();
      return await api.resolvePlayback(deviceId: id, channel: channel);
    } on PlaybackAccessException catch (e) {
      if (!mounted) return null;
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(e.userMessage), duration: const Duration(seconds: 4)),
      );
      switch (e.reason) {
        case PlaybackDenial.premiumRequired:
          unawaited(_syncViewerProfileFromServer());
          if (subscriptionEnabled) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) switchScreen(AppScreen.subscription);
            });
          }
        case PlaybackDenial.updateRequired:
          unawaited(_recheckAppUpdate());
        default:
          break;
      }
      return null;
    }
  }

  void _onSystemBack() {
    if (_playerBackHandler?.call() == true) return;

    if (current == AppScreen.player) {
      _leavePlayer();
      return;
    }

    if (current != AppScreen.home) {
      switchScreen(AppScreen.home);
      return;
    }

    final now = DateTime.now();
    if (_lastExitBackPress != null && now.difference(_lastExitBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastExitBackPress = now;
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text('Bonyeza tena kurudi ili kufunga programu'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> activateSubscription(String phone, String name) async {
    // A payment is already in flight (overlay/poll loop) — ignore re-entrant taps so we
    // never fire two SonicPesa orders for the same phone number back to back.
    if (paymentOverlayOpen) return;

    final trimmedName = name.trim();
    final trimmedPhone = PaymentConfig.normalizeTzLocalPhone(phone) ?? phone.trim();

    if (!PaymentConfig.isValidFullName(trimmedName)) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Andika majina yako kamili (angalau jina na jina la ukoo).')),
      );
      return;
    }
    if (!PaymentConfig.isValidTzLocalPhone(trimmedPhone)) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text(
            'Namba ya simu si sahihi. Tumia 07…, 06… (Halotel 061/062/063/069), au 255…',
          ),
        ),
      );
      return;
    }

    _paymentRetryPhone = trimmedPhone;
    _paymentRetryName = trimmedName;
    userName = trimmedName;
    pendingPhone = trimmedPhone;
    await storage.setName(trimmedName);

    // Register phone on server before payment so webhook orphan recovery can match by MSISDN.
    try {
      await api.syncViewer(deviceId: deviceId, name: trimmedName, phone: trimmedPhone);
    } catch (_) {}

    if (api.isLocalDevelopment) {
      await _runLocalPayment(phone: trimmedPhone, name: trimmedName);
      return;
    }

    // Resume an open order instead of starting a second charge ONLY IF allowNewCharge is false and phone/plan match.
    final pending = await storage.loadPendingPayment();
    if (pending != null && pending.orderId.isNotEmpty && !_paymentAllowNewCharge) {
      if (pending.phone.isNotEmpty && pending.phone != trimmedPhone) {
        await storage.clearPendingPayment();
      } else if (pending.planKey.isNotEmpty && pending.planKey != selectedPlan.id) {
        await storage.clearPendingPayment();
      } else {
        if (pending.planKey.isNotEmpty) {
          for (final p in userPlans) {
            if (p.id == pending.planKey) {
              selectedPlan = p;
              break;
            }
          }
        }
        await _resumeSonicpesaPayment(
          orderId: pending.orderId,
          phone: pending.phone.isNotEmpty ? pending.phone : trimmedPhone,
          name: pending.name.isNotEmpty ? pending.name : trimmedName,
        );
        return;
      }
    }

    await _runSonicpesaPayment(phone: trimmedPhone, name: trimmedName, forceNew: _paymentAllowNewCharge);
  }

  int _planPriceAmount(Plan plan) {
    final digits = plan.price.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(digits) ?? 0;
  }

  /// Dev-only: complete premium via local API (no SonicPesa). Production uses mobile-money push.
  Future<void> _runLocalPayment({required String phone, required String name}) async {
    if (deviceId.isEmpty) {
      throw SonicpesaPaymentException('Kitambulisho cha kifaa hakipo. Anza upya programu.');
    }

    setState(() {
      paymentOverlayOpen = true;
      paymentPhase = SonicpesaPaymentPhase.initiating;
      paymentError = null;
      paymentStatusLine = PaymentConfig.paymentPromptSw;
      subscriptionPaymentSuccess = false;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      setState(() {
        paymentPhase = SonicpesaPaymentPhase.waitingOnPhone;
        paymentStatusLine = 'Inathibitisha malipo (hali ya majaribio ya localhost)…';
      });

      final amount = _planPriceAmount(selectedPlan);
      if (amount <= 0) {
        throw SonicpesaPaymentException('Bei ya mpango si sahihi.');
      }

      await api.recordCompletedTransaction(
        deviceId: deviceId,
        userName: name,
        phone: phone,
        amount: amount.toDouble(),
        method: 'Mobile Money',
        planKey: selectedPlan.id,
      );

      final unlocked = await _applyPremiumUnlock();
      if (!unlocked) {
        throw SonicpesaPaymentException(
          'Malipo yamepokelewa lakini premium haijaanzishwa. Bonyeza Angalia hali.',
          retrySafe: false,
        );
      }
      try {
        await api.syncViewer(deviceId: deviceId, name: name, phone: phone);
        await _syncFromServer(silent: true);
        await _syncViewerProfileFromServer();
      } catch (_) {}

      await _finalizePaymentSuccess();
    } on SonicpesaPaymentException catch (e) {
      if (!mounted) return;
      setState(() {
        paymentPhase = SonicpesaPaymentPhase.failed;
        paymentError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        paymentPhase = SonicpesaPaymentPhase.failed;
        paymentError = 'Imeshindikana kuhifadhi malipo ya majaribio. Hakikisha backend ya localhost inaendesha.';
      });
    }
  }

  /// Resolves premium expiry from status payload + server. Never invents a local end date —
  /// a fake unlock hid failed server grants and left accounts free in admin.
  Future<DateTime?> _resolvePremiumEndAfterPayment({DateTime? fromStatus}) async {
    DateTime? end = fromStatus != null && subService.isPremium(fromStatus) ? fromStatus : null;
    for (var attempt = 0; attempt < 8; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 400 * attempt));
      }
      try {
        final server = await api.fetchPremiumUntil(deviceId);
        end = subService.mergeEndDates(end, server);
      } catch (_) {}
      if (end != null && subService.isPremium(end)) return end;
    }
    if (end != null && subService.isPremium(end)) return end;
    return null;
  }

  Future<bool> _applyPremiumUnlock({DateTime? statusUntil}) async {
    final end = await _resolvePremiumEndAfterPayment(fromStatus: statusUntil);
    if (end == null || !subService.isPremium(end)) {
      return false;
    }
    await storage.setSubscriptionEnd(end);
    if (!mounted) return true;
    setState(() {
      subEnd = end;
      _premiumPlanLabel = selectedPlan.name;
      _premiumAccessSource = 'payment';
      // Keep channels unlocked while profile reconcile lands on the server.
      _paymentUnlockGraceUntil = DateTime.now().add(const Duration(minutes: 5));
    });
    _schedulePremiumExpiryCheck();
    unawaited(_syncPushTopics());
    unawaited(storage.clearPendingPayment());
    return true;
  }

  void _showPremiumUnlockedSnack() {
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: const Text('Premium imewashwa! Channels zote zimefunguliwa.'),
        duration: const Duration(seconds: 4),
        backgroundColor: const Color(0xFF0A3D2E),
      ),
    );
  }

  /// Brief overlay success, then premium status on Fungua zote (no stuck “Malipo Tayari!” screen).
  Future<void> _finalizePaymentSuccess() async {
    if (!mounted) return;
    setState(() {
      paymentPhase = SonicpesaPaymentPhase.success;
      subscriptionPaymentSuccess = true;
      paymentOrderId = null;
      _paymentAllowNewCharge = true;
      _paymentCooldownUntil = null;
    });
    _showPremiumUnlockedSnack();
    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    setState(() => paymentOverlayOpen = false);
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    setState(() => subscriptionPaymentSuccess = false);
  }

  void _dismissPaymentOverlayToStatus() {
    setState(() {
      paymentOverlayOpen = false;
      subscriptionPaymentSuccess = true;
    });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => subscriptionPaymentSuccess = false);
    });
  }

  Future<void> _runSonicpesaPayment({
    required String phone,
    required String name,
    bool forceNew = false,
  }) async {
    if (deviceId.isEmpty) {
      throw SonicpesaPaymentException('Kitambulisho cha kifaa hakipo. Anza upya programu.');
    }

    final cooldown = _paymentCooldownUntil;
    if (!forceNew && cooldown != null && cooldown.isAfter(DateTime.now())) {
      final pending = await storage.loadPendingPayment();
      if (pending != null) {
        await _resumeSonicpesaPayment(
          orderId: pending.orderId,
          phone: pending.phone.isNotEmpty ? pending.phone : phone,
          name: pending.name.isNotEmpty ? pending.name : name,
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        paymentOverlayOpen = true;
        paymentPhase = SonicpesaPaymentPhase.failed;
        paymentError =
            'Subiri kidogo — ombi la awali linaweza bado kuendelea. Angalia simu yako, kisha bonyeza Angalia hali.';
        _paymentAllowNewCharge = false;
      });
      return;
    }

    setState(() {
      paymentOverlayOpen = true;
      paymentPhase = SonicpesaPaymentPhase.initiating;
      paymentError = null;
      paymentStatusLine = PaymentConfig.paymentPromptFor(phone);
      subscriptionPaymentSuccess = false;
      _paymentAllowNewCharge = false;
    });

    try {
      final init = await sonicPay.initiate(
        deviceId: deviceId,
        userName: name,
        phone: phone,
        planKey: selectedPlan.id,
        forceNew: forceNew,
      );

      await storage.savePendingPayment(
        orderId: init.orderId,
        phone: phone,
        name: name,
        planKey: selectedPlan.id,
      );

      if (!mounted) return;

      if (init.completed) {
        final unlocked = await _applyPremiumUnlock(statusUntil: init.premiumUntil);
        if (!unlocked) {
          // Payment succeeded on provider but grant not visible yet — keep polling this order.
          setState(() {
            paymentOrderId = init.orderId;
            paymentPhase = SonicpesaPaymentPhase.waitingOnPhone;
            paymentStatusLine = 'Malipo yamepokelewa — inafungua channels…';
          });
          await _pollUntilDone(
            orderId: init.orderId,
            phone: phone,
            name: name,
          );
          return;
        }
        try {
          await api.syncViewer(deviceId: deviceId, name: name, phone: phone);
          await _syncFromServer(silent: true);
          await _syncViewerProfileFromServer();
        } catch (_) {}
        await _finalizePaymentSuccess();
        return;
      }

      setState(() {
        paymentOrderId = init.orderId;
        paymentPhase = SonicpesaPaymentPhase.waitingOnPhone;
        paymentStatusLine = init.message.isNotEmpty
            ? init.message
            : PaymentConfig.paymentPromptFor(phone);
      });

      await _pollUntilDone(
        orderId: init.orderId,
        phone: phone,
        name: name,
      );
    } on SonicpesaPaymentException catch (e) {
      if (e.orderId != null && e.orderId!.isNotEmpty) {
        await storage.savePendingPayment(
          orderId: e.orderId!,
          phone: phone,
          name: name,
          planKey: selectedPlan.id,
        );
        if (mounted) setState(() => paymentOrderId = e.orderId);
      }
      if (e.cooldownSeconds != null && e.cooldownSeconds! > 0) {
        _paymentCooldownUntil = DateTime.now().add(Duration(seconds: e.cooldownSeconds!));
      }
      if (!mounted) return;
      setState(() {
        paymentPhase = SonicpesaPaymentPhase.failed;
        paymentError = e.message;
        // Only allow a brand-new STK push when the server says it is safe and no order exists.
        _paymentAllowNewCharge = e.retrySafe && (paymentOrderId == null || paymentOrderId!.isEmpty);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        paymentPhase = SonicpesaPaymentPhase.failed;
        paymentError = 'Hitilafu ya mtandao. Bonyeza Angalia hali — usilipie tena bado.';
        _paymentAllowNewCharge = false;
      });
    }
  }

  /// Poll an existing order (never creates a new SonicPesa charge).
  Future<void> _resumeSonicpesaPayment({
    required String orderId,
    required String phone,
    required String name,
  }) async {
    if (deviceId.isEmpty) return;

    setState(() {
      paymentOverlayOpen = true;
      paymentOrderId = orderId;
      paymentPhase = SonicpesaPaymentPhase.waitingOnPhone;
      paymentError = null;
      paymentStatusLine = 'Inaangalia hali ya malipo yaliyopo…';
      subscriptionPaymentSuccess = false;
      _paymentAllowNewCharge = false;
    });

    try {
      await storage.savePendingPayment(
        orderId: orderId,
        phone: phone,
        name: name,
        planKey: selectedPlan.id,
      );
      await _pollUntilDone(orderId: orderId, phone: phone, name: name);
    } on SonicpesaPaymentException catch (e) {
      if (!mounted) return;
      setState(() {
        paymentPhase = SonicpesaPaymentPhase.failed;
        paymentError = e.message;
        _paymentAllowNewCharge = e.retrySafe;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        paymentPhase = SonicpesaPaymentPhase.failed;
        paymentError = 'Hitilafu ya mtandao. Bonyeza Angalia hali.';
        _paymentAllowNewCharge = false;
      });
    }
  }

  Future<void> _pollUntilDone({
    required String orderId,
    required String phone,
    required String name,
  }) async {
    const maxAttempts = 90;
    for (var i = 0; i < maxAttempts; i++) {
      final delay = i < 20 ? const Duration(seconds: 1) : const Duration(seconds: 2);
      await Future.delayed(delay);
      if (!mounted || !paymentOverlayOpen) return;

      final completed = await _pollPaymentOnce(
        orderId: orderId,
        phone: phone,
        name: name,
      );
      if (completed) return;

      if (!mounted) return;
      setState(() {
        paymentStatusLine = i < 8
            ? PaymentConfig.paymentPromptFor(phone)
            : 'Bado tunasubiri uthibitisho wa ${PaymentConfig.networkLabel(PaymentConfig.detectNetwork(phone))}…';
      });
    }

    final recovered = await _tryRecoverPremiumFromServer();
    if (recovered) {
      await _finalizePaymentSuccess();
      return;
    }

    // Keep pending order so resume/webhook can still unlock — do not push a second STK yet.
    if (mounted) {
      setState(() {
        _paymentAllowNewCharge = false;
        _paymentCooldownUntil = DateTime.now().add(const Duration(minutes: 5));
      });
    }
    throw SonicpesaPaymentException(
      'Bado tunasubiri uthibitisho. Bonyeza Angalia hali — usianze malipo mapya bado.',
      retrySafe: false,
      orderId: orderId,
      cooldownSeconds: 300,
    );
  }

  /// One status poll — returns true when payment completed and premium applied.
  Future<bool> _pollPaymentOnce({
    required String orderId,
    required String phone,
    required String name,
  }) async {
    late final SonicpesaStatusResult status;
    try {
      status = await sonicPay.checkStatus(
        deviceId: deviceId,
        orderId: orderId,
        userName: name,
        phone: phone,
        planKey: selectedPlan.id,
        amount: _planPriceAmount(selectedPlan),
      );
    } on SonicpesaPaymentException catch (e) {
      final code = e.statusCode;
      // Payment charged but grant briefly failed — keep waiting / recover from server.
      if (e.paymentReceived || code == 500) {
        if (mounted) {
          setState(() => paymentStatusLine = 'Malipo yamepokelewa — inafungua channels…');
        }
        return _completePaymentIfPremiumReady();
      }
      if (code == 502 || code == 503 || code == 504) {
        if (mounted) {
          setState(() => paymentStatusLine = 'Seva inaendelea kuchakata malipo…');
        }
        return _completePaymentIfPremiumReady();
      }
      rethrow;
    }

    if (status.completed) {
      final unlocked = await _applyPremiumUnlock(statusUntil: status.premiumUntil);
      if (!unlocked) {
        if (mounted) {
          setState(() => paymentStatusLine = 'Malipo yamepokelewa — inafungua channels…');
        }
        return _completePaymentIfPremiumReady();
      }
      try {
        await api.syncViewer(deviceId: deviceId, name: name, phone: phone);
        await _syncFromServer(silent: true);
        await _syncViewerProfileFromServer();
      } catch (_) {}
      return _completePaymentIfPremiumReady();
    }

    if (status.failed) {
      await storage.clearPendingPayment();
      if (mounted) {
        setState(() {
          paymentOrderId = null;
          _paymentAllowNewCharge = true;
          _paymentCooldownUntil = null;
        });
      }
      throw SonicpesaPaymentException(
        status.message ?? 'Malipo yameghairiwa au kukataliwa.',
        retrySafe: true,
      );
    }

    if (mounted) {
      setState(() => paymentStatusLine = _statusHint(status.paymentStatus));
    }
    return false;
  }

  Future<bool> _completePaymentIfPremiumReady() async {
    if (!premium && !subService.isPremium(subEnd)) {
      final ok = await _tryRecoverPremiumFromServer();
      if (!ok) return false;
    }
    if (paymentOverlayOpen) {
      await _finalizePaymentSuccess();
    } else {
      await storage.clearPendingPayment();
      if (mounted) {
        setState(() => subscriptionPaymentSuccess = true);
        _showPremiumUnlockedSnack();
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => subscriptionPaymentSuccess = false);
        });
      }
    }
    return true;
  }

  /// After webhook or slow provider — confirm premium on server without a fresh payment.
  Future<bool> _tryRecoverPremiumFromServer() async {
    try {
      final serverEnd = await api.fetchPremiumUntil(deviceId);
      if (serverEnd != null && subService.isPremium(serverEnd)) {
        final unlocked = await _applyPremiumUnlock(statusUntil: serverEnd);
        if (!unlocked) return false;
        try {
          await _syncViewerProfileFromServer();
        } catch (_) {}
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Resume polling when user closed overlay or app was backgrounded during USSD push.
  Future<void> _recoverPendingPayment({bool silent = false}) async {
    if (paymentOverlayOpen || premium || deviceId.isEmpty) return;
    final pending = await storage.loadPendingPayment();
    if (pending == null) return;

    if (pending.planKey.isNotEmpty) {
      for (final p in userPlans) {
        if (p.id == pending.planKey) {
          selectedPlan = p;
          break;
        }
      }
    }

    if (!silent && mounted) {
      setState(() => paymentStatusLine = 'Inaangalia malipo yaliyosalia…');
    }

    for (var i = 0; i < 12; i++) {
      if (!mounted || premium) return;
      final done = await _pollPaymentOnce(
        orderId: pending.orderId,
        phone: pending.phone,
        name: pending.name,
      );
      if (done) return;
      await Future.delayed(const Duration(seconds: 2));
    }

    if (await _tryRecoverPremiumFromServer()) {
      if (mounted) {
        setState(() => subscriptionPaymentSuccess = true);
        _showPremiumUnlockedSnack();
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => subscriptionPaymentSuccess = false);
        });
      }
      await storage.clearPendingPayment();
    }
  }

  String _statusHint(String status) {
    switch (status.toUpperCase().replaceAll(' ', '')) {
      case 'INPROGRESS':
      case 'IN_PROGRESS':
      case 'PROCESSING':
        return 'Malipo yanaendelea…';
      case 'PENDING':
      case 'INITIATED':
        return 'Inasubiri uthibitisho kwenye simu yako…';
      case 'SUCCESS':
      case 'COMPLETED':
      case 'PAID':
        return 'Malipo yamekamilika…';
      case 'CANCELLED':
      case 'USERCANCELLED':
        return 'Malipo yameghairiwa kwenye simu.';
      case 'REJECTED':
      case 'FAILED':
      case 'FAILURE':
      case 'EXPIRED':
        return 'Malipo hayajakamilika. Jaribu tena.';
      default:
        return 'Inasubiri uthibitisho kwenye simu yako…';
    }
  }

  void _cancelPaymentOverlay() {
    setState(() {
      paymentOverlayOpen = false;
      paymentPhase = SonicpesaPaymentPhase.cancelled;
    });
    unawaited(_recoverPendingPayment(silent: true));
  }

  Future<void> _retryPayment() async {
    final phone = _paymentRetryPhone;
    final name = _paymentRetryName;
    if (phone == null || name == null) return;

    final pending = await storage.loadPendingPayment();
    final existingOrder = (paymentOrderId?.trim().isNotEmpty == true)
        ? paymentOrderId!.trim()
        : pending?.orderId;

    // Default: resume / check existing order ONLY IF new charge is disallowed.
    if (existingOrder != null && existingOrder.isNotEmpty && !_paymentAllowNewCharge && pending != null) {
      await _resumeSonicpesaPayment(
        orderId: existingOrder,
        phone: pending.phone.isNotEmpty == true ? pending.phone : phone,
        name: pending.name.isNotEmpty == true ? pending.name : name,
      );
      return;
    }

    // Confirmed failure (or no open order or user allowed new charge) — safe to start a fresh STK push.
    await _runSonicpesaPayment(
      phone: phone,
      name: name,
      forceNew: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WASHA TV',
      theme: AppTheme.build(),
      scaffoldMessengerKey: _scaffoldMessengerKey,
      home: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onSystemBack();
        },
        child: Scaffold(
        body: bootLoading
            ? _bootLoadingScreen()
            : appUpdate.updateRequired
                ? ForceUpdateScreen(
                    status: appUpdate,
                    onRecheck: _recheckAppUpdate,
                  )
                : maintenanceMode
                ? _maintenanceScreen()
                : Stack(
                children: [
                  const CinematicBackground(),
                  SafeArea(
                    top: !_playerFullscreen,
                    bottom: !_playerFullscreen,
                    left: !_playerFullscreen,
                    right: !_playerFullscreen,
                    child: Column(
                      children: [
                        if (syncRefreshing && !_playerFullscreen)
                          const LinearProgressIndicator(
                            minHeight: 2,
                            backgroundColor: AppTheme.white07,
                            color: AppTheme.cyan,
                          ),
                        if (bootstrapError != null && !_noInternetVisible && !_playerFullscreen) _bootstrapErrorBanner(),
                        Expanded(
                          child: ListenableBuilder(
                            listenable: AppSettingsService.instance,
                            builder: (context, _) => _buildScreen(),
                          ),
                        ),
                        if (current != AppScreen.player)
                          BottomNav(
                            current: current,
                            onTap: switchScreen,
                          ),
                      ],
                    ),
                  ),
                  if (paymentOverlayOpen)
                    SubscriptionScreen.buildSonicpesaPaymentOverlay(
                      phase: paymentPhase,
                      planLabel: selectedPlan.name,
                      amountLabel: selectedPlan.price,
                      statusLine: paymentStatusLine,
                      errorMessage: paymentError,
                      onCancel: _cancelPaymentOverlay,
                      onRetry: paymentPhase == SonicpesaPaymentPhase.failed ? () => unawaited(_retryPayment()) : null,
                      onContinue: paymentPhase == SonicpesaPaymentPhase.success ? _dismissPaymentOverlayToStatus : null,
                      allowNewCharge: _paymentAllowNewCharge,
                    ),
                  if (_noInternetVisible)
                    Positioned.fill(
                      child: NoInternetModal(
                        isRetrying: _noInternetRetrying,
                        onRetry: () => unawaited(_retryFromNoInternetModal()),
                      ),
                    ),
                ],
              ),
        ),
      ),
    );
  }

  Future<void> _retryBootstrapAfterError() async {
    api.resetLightweightPollBackoff();
    setState(() {
      bootstrapError = null;
      bootstrapFailureDetail = null;
      bootLoading = true;
    });
    await _init();
  }

  Future<void> _retryFromNoInternetModal() async {
    if (_noInternetRetrying) return;
    setState(() => _noInternetRetrying = true);
    api.resetLightweightPollBackoff();
    setState(() {
      bootstrapError = null;
      bootstrapFailureDetail = null;
      bootLoading = false;
    });
    await _init();
    if (mounted && !_noInternetVisible) return;
    // If _init succeeded, _noInternetVisible is already false via setState in _init.
    // If still failing, keep modal open and reset spinner.
    if (mounted) setState(() => _noInternetRetrying = false);
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
            color: AppTheme.surfaceElevated.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.cloud_off_rounded, color: AppTheme.amber, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Seva haipatikani', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.textPrimary)),
                    const SizedBox(height: 5),
                    Text(msg, style: AppTheme.bodyMedium.copyWith(fontSize: 12)),
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
          carouselConfigVersion: _effectiveImageCacheEpoch,
          carouselIndex: carousel,
          onCarouselDot: (i) => setState(() => carousel = i),
          onOpenPlayer: _openPlayer,
          onOpenSubscription: () => switchScreen(AppScreen.subscription),
          premium: premium,
          displayName: _displayName,
          channelDisplay: AppSettingsService.instance.settings.channelDisplay,
        );
      case AppScreen.player:
        return PlayerScreen(
          channels: channels,
          channel: selectedChannel,
          resolveStream: _resolveChannelStream,
          onBack: _leavePlayer,
          onBackHandlerChanged: (handler) => _playerBackHandler = handler,
          onFullscreenChanged: (value) {
            if (_playerFullscreen == value) return;
            setState(() => _playerFullscreen = value);
            if (!value) _lockShellPortrait();
          },
        );
      case AppScreen.categories:
        return CategoriesScreen(
          channels: channels,
          channelImageCacheEpoch: _effectiveImageCacheEpoch,
          premium: premium,
          onOpenPlayer: _openPlayer,
          onOpenSubscription: () => switchScreen(AppScreen.subscription),
        );
      case AppScreen.profile:
        return ProfileScreen(
          premium: premium,
          userName: _displayName,
          deviceId: deviceId,
          endDate: subEnd,
          planLabel: _premiumPlanLabel,
          accessSource: _premiumAccessSource,
          supportWhatsapp: supportWhatsapp,
          onOpenSubscription: () => switchScreen(AppScreen.subscription),
        );
      case AppScreen.subscription:
        if (!subscriptionEnabled) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Usajili wa premium umezimwa kwa sasa.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15),
              ),
            ),
          );
        }
        return SubscriptionScreen(
          plans: userPlans,
          premium: premium,
          selectedPlan: selectedPlan,
          endDate: subEnd,
          planLabel: _premiumPlanLabel,
          accessSource: _premiumAccessSource,
          userName: _displayName,
          paymentSucceeded: subscriptionPaymentSuccess,
          localPaymentsOnly: api.isLocalDevelopment,
          onPlanChange: (p) => setState(() => selectedPlan = p),
          onPay: activateSubscription,
        );
      case AppScreen.settings:
        return SettingsScreen(
          premium: premium,
          busy: syncRefreshing,
          onSaveAndRefresh: (_) => _fullAppRefresh(),
          onUpdateData: (_) => _fullAppRefresh(),
          onClearCaches: _clearAppCaches,
          onCheckPayment: _checkPaymentFromSettings,
        );
    }
  }

  Future<void> _syncNativePlaybackSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final settings = AppSettingsService.instance;
      await NativeAndroidPlayer.syncUserPlaybackSettings(
        dataSaver: settings.settings.dataSaver,
        defaultQuality: settings.resolvePlaybackQuality(
          serverDefault: 'AUTO',
        ),
        videoZoomMode: settings.settings.videoZoom.nativeMode,
      );
    } catch (_) {}
  }

  Future<void> _clearAppCaches() async {
    await AppCacheService.instance.clearAll(api: api);
    if (!mounted) return;
    setState(() => _imageCacheBust++);
  }

  Future<void> _fullAppRefresh() async {
    await AppCacheService.instance.clearAll(api: api);
    if (!mounted) return;
    setState(() {
      _imageCacheBust++;
      pendingConfigSync = false;
      bootstrapError = null;
      bootstrapFailureDetail = null;
    });
    await AppSettingsService.instance.load();
    await _syncNativePlaybackSettings();
    await _syncViewerProfileFromServer();
    await _recoverPendingPayment(silent: true);
    await _tryRecoverPremiumFromServer();
    await _syncFromServer(silent: false, forceFull: true);
    if (!mounted) return;
    setState(() {
      current = AppScreen.home;
      carousel = 0;
    });
  }

  Future<String> _checkPaymentFromSettings() async {
    await _syncViewerProfileFromServer();
    await _recoverPendingPayment(silent: false);
    final recovered = await _tryRecoverPremiumFromServer();
    if (!mounted) return '';
    if (premium || recovered) {
      setState(() {});
      return 'Premium imethibitishwa! Channels zimefunguliwa.';
    }
    return 'Hakuna malipo mapya yaliyothibitishwa. Jaribu tena baada ya dakika chache au wasiliana nasi.';
  }

  Future<void> _recheckAppUpdate() async {
    final status = await api.fetchAppUpdateStatus();
    if (status != null && mounted) {
      setState(() => appUpdate = status);
      if (!status.updateRequired) {
        // Pull full catalog again after update is cleared.
        await _syncFromServer(silent: false, forceFull: true);
      }
      return;
    }
    // Fallback: full bootstrap recheck.
    await _init();
  }

  Widget _bootLoadingScreen() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const CinematicBackground(),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: AppTheme.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.cyan.withValues(alpha: 0.35),
                      blurRadius: 28,
                    ),
                  ],
                ),
                child: const Icon(Icons.play_arrow_rounded, color: AppTheme.background, size: 36),
              ),
              const SizedBox(height: 28),
              Text('WASHA TV', style: AppTheme.displayLarge.copyWith(fontSize: 28)),
              const SizedBox(height: 8),
              Text('Inapakia...', style: AppTheme.bodyMedium),
              const SizedBox(height: 24),
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _maintenanceScreen() {
    return Stack(
      fit: StackFit.expand,
      children: [
        const CinematicBackground(),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: AppTheme.amber.withValues(alpha: 0.15),
                    border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.build_circle_outlined, size: 36, color: AppTheme.amber),
                ),
                const SizedBox(height: 20),
                Text(siteName, style: AppTheme.displayMedium),
                const SizedBox(height: 12),
                Text(
                  'Programu iko katika matengenezo. Tafadhali rudi baadaye.',
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.tonal(
                  onPressed: () => unawaited(_syncFromServer(silent: false)),
                  child: const Text('Jaribu tena'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openPlayer(Channel c) {
    if (c.premium && !premium) {
      if (subscriptionEnabled) {
        switchScreen(AppScreen.subscription);
      }
      return;
    }
    if (current != AppScreen.player) {
      _returnScreen = current;
    }
    setState(() {
      selectedChannel = c;
      current = AppScreen.player;
    });
    _pauseConfigPoller();
  }
}

