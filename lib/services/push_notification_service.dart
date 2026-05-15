import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Must match Supasoka backend [pushNotifications.ts] `channelId` and FCM topics.
const String kSupasokaFcmAndroidChannelId = 'supasoka_high_importance';
const String kSupasokaTopicAllUsers = 'all_users';
const String kSupasokaTopicPremiumUsers = 'premium_users';
const String kSupasokaTopicFreeUsers = 'free_users';

const _androidChannelName = 'Washa TV Alerts';
const _androidChannelDescription = 'Taarifa kutoka Supasoka / Washa (mechi, channel, akaunti)';

final _localNotifications = FlutterLocalNotificationsPlugin();
const _prefsNotifPrompted = 'washa_notif_prompted_v1';
const _prefsDirectTopic = 'washa_direct_user_topic_v1';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

/// Shared Firebase project + topics with Supasoka — pushes from Supasoka admin reach Washa too.
class PushNotificationService {
  PushNotificationService._();

  static Future<void> initialize() async {
    if (kIsWeb) return;

    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    const androidChannel = AndroidNotificationChannel(
      kSupasokaFcmAndroidChannelId,
      _androidChannelName,
      description: _androidChannelDescription,
      importance: Importance.high,
    );
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);

    final messaging = FirebaseMessaging.instance;
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    if (kDebugMode) {
      final token = await messaging.getToken();
      debugPrint('Washa FCM token: $token');
    }

    await messaging.subscribeToTopic(kSupasokaTopicAllUsers);

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
    FirebaseMessaging.onMessageOpenedApp.listen(_logOpenedNotification);

    final initial = await messaging.getInitialMessage();
    if (initial != null) _logOpenedNotification(initial);
  }

  static Future<bool> shouldShowPermissionPrompt() async {
    if (kIsWeb) return false;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final allowed = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (allowed) return false;
    return true;
  }

  static Future<bool> requestPermissionFromPrompt() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsNotifPrompted, true);
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final allowed = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (allowed) {
      final messaging = FirebaseMessaging.instance;
      await messaging.subscribeToTopic(kSupasokaTopicAllUsers);
    }
    return allowed;
  }

  static Future<void> markPermissionPromptSeen() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsNotifPrompted, true);
  }

  static Future<void> syncAudienceTopics({required bool isPremium}) async {
    if (kIsWeb) return;
    final messaging = FirebaseMessaging.instance;
    if (isPremium) {
      await messaging.subscribeToTopic(kSupasokaTopicPremiumUsers);
      await messaging.unsubscribeFromTopic(kSupasokaTopicFreeUsers);
    } else {
      await messaging.subscribeToTopic(kSupasokaTopicFreeUsers);
      await messaging.unsubscribeFromTopic(kSupasokaTopicPremiumUsers);
    }
  }

  /// Per-device topic for future targeted pushes (`user_{id}` — same rule as Supasoka).
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
    final n = message.notification;
    if (n == null) return;

    const android = AndroidNotificationDetails(
      kSupasokaFcmAndroidChannelId,
      _androidChannelName,
      channelDescription: _androidChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const details = NotificationDetails(android: android);

    await _localNotifications.show(
      message.hashCode,
      n.title ?? 'Washa TV',
      n.body ?? '',
      details,
      payload: jsonEncode(message.data),
    );
  }

  static void _logOpenedNotification(RemoteMessage message) {
    if (kDebugMode) debugPrint('Washa notification opened: ${message.data}');
  }
}
