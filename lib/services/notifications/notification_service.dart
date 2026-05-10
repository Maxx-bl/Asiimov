import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

/// Top-level background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background notifications are handled automatically by FCM on Android
  // No extra logic needed here unless you want custom processing
  debugPrint('Background message received: ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// The ID of the user whose chat is currently open (to suppress notifications)
  String? _activeChatUserId;

  /// Callback when user taps a notification — receives the full data map
  void Function(Map<String, dynamic> data)? onNotificationTap;

  /// Android notification channel for chat messages
  static const AndroidNotificationChannel _chatChannel =
      AndroidNotificationChannel(
    'chat_messages',
    'Chat Messages',
    description: 'Notifications for new chat messages',
    importance: Importance.high,
    playSound: true,
  );

  /// Initialize the notification service
  Future<void> initialize() async {
    // Request permissions
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Create the Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_chatChannel);

    // Initialize local notifications plugin
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // We handle foreground notifications manually via local notifications
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    // Listen to foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Listen to notification taps when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    // Check if app was opened from a terminated state via notification
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationOpen(initialMessage);
    }
  }

  /// Set the active chat user and clear their notifications
  void setActiveChatUser(String? userId) {
    _activeChatUserId = userId;
    if (userId != null) {
      clearNotificationsForUser(userId);
    }
  }

  /// Clear all notifications from a specific sender (by tag)
  Future<void> clearNotificationsForUser(String senderUserId) async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.cancel(0, tag: senderUserId);
    }
  }

  /// Handle foreground messages — show notification unless we're in that conversation
  void _handleForegroundMessage(RemoteMessage message) {
    final senderID = message.data['senderID'];
    final type = message.data['type'];

    // Don't show notification if we're already chatting with this person
    if (type == 'chat_message' && senderID != null && senderID == _activeChatUserId) {
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    // Use same tagging logic as sender side
    final String tag = type == 'chat_message' && senderID != null
        ? senderID 
        : DateTime.now().millisecondsSinceEpoch.toString();

    _localNotifications.show(
      senderID?.hashCode ?? 0,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _chatChannel.id,
          _chatChannel.name,
          channelDescription: _chatChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          tag: tag,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// Handle notification tap when app is in background/foreground
  void _handleNotificationOpen(RemoteMessage message) {
    if (onNotificationTap != null) {
      onNotificationTap!(message.data);
    }
  }

  /// Handle tap on local notification (foreground notifications)
  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if (onNotificationTap != null) {
        onNotificationTap!(data);
      }
    } catch (e) {
      debugPrint('Error decoding notification payload: $e');
    }
  }
}
