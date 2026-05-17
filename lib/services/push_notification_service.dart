import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'public_api_service.dart';

/// Must match Supasoka backend [pushNotifications.ts] `channelId` and FCM topics.
const String kSupasokaFcmAndroidChannelId = 'supasoka_high_importance';
const String kSupasokaTopicAllUsers = 'all_users';
const String kSupasokaTopicPremiumUsers = 'premium_users';
const String kSupasokaTopicFreeUsers = 'free_users';

const _androidChannelName = 'Washa TV Alerts';
const _androidChannelDescription =
    'Taarifa kutoka admin — mechi, channel, na ujumbe wa akaunti (hata baada ya wiki nyingi)';

const _prefsNotifPrompted = 'washa_notif_prompted_v1';
const _prefsDirectTopic = 'washa_direct_user_topic_v1';
const _prefsPushPremium = 'washa_push_premium_v1';
const _prefsPushDeviceId = 'washa_push_device_id_v1';
const _prefsLastFcmToken = 'washa_last_fcm_token_v1';

final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
bool _backgroundLocalPluginReady = false;

/// Top-level handler — runs when app is killed/background; keeps alerts deliverable long-term.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Notification payload is shown by Android/iOS when app is not in foreground.
  if (message.notification != null) return;
  await _ensureBackgroundLocalNotifications();
  await _displayLocalNotification(message);
}

Future<void> _ensureBackgroundLocalNotifications() async {
  if (_backgroundLocalPluginReady) return;
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await _localNotifications.initialize(const InitializationSettings(android: androidSettings));
  const androidChannel = AndroidNotificationChannel(
    kSupasokaFcmAndroidChannelId,
    _androidChannelName,
    description: _androidChannelDescription,
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  final androidPlugin = _localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(androidChannel);
  _backgroundLocalPluginReady = true;
}

Future<void> _displayLocalNotification(RemoteMessage message) async {
  final n = message.notification;
  final data = message.data;
  final title = n?.title ?? data['title']?.toString() ?? 'WASHA TV';
  final body = n?.body ?? data['body']?.toString() ?? data['message']?.toString() ?? '';

  const android = AndroidNotificationDetails(
    kSupasokaFcmAndroidChannelId,
    _androidChannelName,
    channelDescription: _androidChannelDescription,
    importance: Importance.max,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
    visibility: NotificationVisibility.public,
    category: AndroidNotificationCategory.message,
  );
  const details = NotificationDetails(android: android);

  await _localNotifications.show(
    message.messageId?.hashCode ?? message.hashCode,
    title,
    body,
    details,
    payload: jsonEncode(data),
  );
}

/// Shared Firebase project + topics with Supasoka — pushes from admin reach Washa too.
class PushNotificationService {
  PushNotificationService._();

  static PublicApiService? _api;

  static Future<void> initialize({PublicApiService? api}) async {
    if (kIsWeb) return;

    _api = api;

    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    await FirebaseMessaging.instance.setAutoInitEnabled(true);

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    const androidChannel = AndroidNotificationChannel(
      kSupasokaFcmAndroidChannelId,
      _androidChannelName,
      description: _androidChannelDescription,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await androidPlugin?.requestNotificationsPermission();
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(_logOpenedNotification);

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_onTokenRefreshed(token));
    });

    final initial = await messaging.getInitialMessage();
    if (initial != null) _logOpenedNotification(initial);

    if (kDebugMode) {
      final token = await messaging.getToken();
      debugPrint('Washa FCM token: $token');
    }
  }

  /// Call after boot, resume, premium change, or permission grant — re-binds FCM topics + server token.
  static Future<void> ensureRegistered({
    required String deviceId,
    required bool isPremium,
    PublicApiService? api,
  }) async {
    if (kIsWeb) return;
    final id = deviceId.trim();
    if (id.isEmpty) return;

    _api = api ?? _api;

    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final allowed = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!allowed) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsPushDeviceId, id);
    await prefs.setBool(_prefsPushPremium, isPremium);

    await refreshAllSubscriptions(isPremium: isPremium, deviceId: id);

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _registerTokenOnServer(deviceId: id, token: token);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Washa FCM getToken: $e');
    }
  }

  static Future<void> refreshAllSubscriptions({
    required bool isPremium,
    required String deviceId,
  }) async {
    if (kIsWeb) return;
    final messaging = FirebaseMessaging.instance;

    await messaging.subscribeToTopic(kSupasokaTopicAllUsers);

    if (isPremium) {
      await messaging.subscribeToTopic(kSupasokaTopicPremiumUsers);
      await messaging.unsubscribeFromTopic(kSupasokaTopicFreeUsers);
    } else {
      await messaging.subscribeToTopic(kSupasokaTopicFreeUsers);
      await messaging.unsubscribeFromTopic(kSupasokaTopicPremiumUsers);
    }

    await syncDirectUserTopic(deviceId);
  }

  static Future<void> _onTokenRefreshed(String token) async {
    if (kIsWeb || token.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(_prefsPushDeviceId) ?? '';
    final isPremium = prefs.getBool(_prefsPushPremium) ?? false;
    if (deviceId.isEmpty) {
      await prefs.setString(_prefsLastFcmToken, token);
      return;
    }
    try {
      await refreshAllSubscriptions(isPremium: isPremium, deviceId: deviceId);
      await _registerTokenOnServer(deviceId: deviceId, token: token);
    } catch (e) {
      if (kDebugMode) debugPrint('Washa FCM token refresh: $e');
    }
  }

  static Future<void> _registerTokenOnServer({
    required String deviceId,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_prefsLastFcmToken);
    if (last == token) return;

    final api = _api;
    if (api == null) return;

    try {
      await api.registerFcmToken(deviceId: deviceId, fcmToken: token);
      await prefs.setString(_prefsLastFcmToken, token);
    } catch (e) {
      if (kDebugMode) debugPrint('Washa FCM server register: $e');
    }
  }

  static Future<bool> shouldShowPermissionPrompt() async {
    if (kIsWeb) return false;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final allowed = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (allowed) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsNotifPrompted) == true) return false;
    return true;
  }

  static Future<bool> requestPermissionFromPrompt({
    String? deviceId,
    bool isPremium = false,
  }) async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsNotifPrompted, true);
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final allowed = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (allowed) {
      final id = deviceId?.trim() ?? prefs.getString(_prefsPushDeviceId) ?? '';
      if (id.isNotEmpty) {
        await ensureRegistered(deviceId: id, isPremium: isPremium);
      } else {
        await refreshAllSubscriptions(isPremium: isPremium, deviceId: '');
        await messagingSubscribeAllUsersOnly();
      }
    }
    return allowed;
  }

  static Future<void> messagingSubscribeAllUsersOnly() async {
    if (kIsWeb) return;
    await FirebaseMessaging.instance.subscribeToTopic(kSupasokaTopicAllUsers);
  }

  static Future<void> markPermissionPromptSeen() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsNotifPrompted, true);
  }

  static Future<void> syncAudienceTopics({required bool isPremium}) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(_prefsPushDeviceId) ?? '';
    if (deviceId.isEmpty) {
      await refreshAllSubscriptions(isPremium: isPremium, deviceId: '');
      return;
    }
    await ensureRegistered(deviceId: deviceId, isPremium: isPremium);
  }

  /// Per-device topic for targeted admin pushes (`user_{deviceId}` — same rule as Supasoka).
  static Future<void> syncDirectUserTopic(String deviceId) async {
    if (kIsWeb) return;
    final raw = deviceId.trim();
    if (raw.isEmpty) return;
    final topic = 'user_${raw.replaceAll(RegExp(r'[^a-zA-Z0-9\-_.~%]'), '_')}';
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(_prefsDirectTopic);
    final messaging = FirebaseMessaging.instance;
    if (old != null && old.isNotEmpty && old != topic) {
      try {
        await messaging.unsubscribeFromTopic(old);
      } catch (_) {}
    }
    await messaging.subscribeToTopic(topic);
    await prefs.setString(_prefsDirectTopic, topic);
  }

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
    await _displayLocalNotification(message);
  }

  static void _logOpenedNotification(RemoteMessage message) {
    if (kDebugMode) debugPrint('Washa notification opened: ${message.data}');
  }
}
