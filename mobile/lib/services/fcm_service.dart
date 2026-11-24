import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/repositories/alert_repository.dart';

class FcmService {
  static final _messaging = FirebaseMessaging.instance;
  static final _repository = AlertRepository();
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'financial_alerts';
  static const _channelName = 'Financial Alerts';

  static bool _listening = false;
  static void Function(Map<String, dynamic> data)? _onOpen;

  /// [authToken] is read on every call because the access token is renewed
  /// while the app runs. Runs again after each login; the listeners are
  /// added only once. [onOpen] gets the data of a tapped notification.
  static Future<void> init(
    String? Function() authToken, {
    required void Function(Map<String, dynamic> data) onOpen,
  }) async {
    if (kIsWeb) return;
    _onOpen = onOpen;
    await _initLocalNotifications();

    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    final fcmToken = await _messaging.getToken();
    final token = authToken();
    if (fcmToken == null || token == null) return;

    try {
      await _repository.registerToken(token, fcmToken);
    } catch (e) {
      debugPrint('FCM token registration failed: $e');
    }

    if (_listening) return;
    _listening = true;

    _messaging.onTokenRefresh.listen((newToken) async {
      final token = authToken();
      if (token == null) return;
      try {
        await _repository.registerToken(token, newToken);
      } catch (e) {
        debugPrint('FCM token refresh registration failed: $e');
      }
    });

    // In the foreground the system shows nothing, so the push is shown as a
    // local notification that carries the same data.
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      _showLocalNotification(
        title: notification.title ?? 'Financial Alert',
        body: notification.body ?? '',
        data: message.data,
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) => _onOpen?.call(message.data));

    // A push tapped while the app was closed started it.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onOpen?.call(initial.data);
  }

  static Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        _onOpen?.call(jsonDecode(payload) as Map<String, dynamic>);
      },
    );

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: jsonEncode(data),
    );
  }
}
