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
  void Function(Map<String, dynamic> data)? _onNotificationTap;
  Map<String, dynamic>? _initialData;

  set onNotificationTap(void Function(Map<String, dynamic> data) handler) {
    _onNotificationTap = handler;
    // If we have initial data waiting, handle it now
    if (_initialData != null) {
      _onNotificationTap!(_initialData!);
      _initialData = null;
    }
  }

  /// Store message history for active notifications to support MessagingStyle
  /// senderID -> List of messages
  final Map<String, List<Message>> _messageHistory = {};

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
      await androidPlugin.cancel(senderUserId.hashCode);
      _messageHistory.remove(senderUserId);
    }
  }

  /// Handle foreground messages — show notification unless we're in that conversation
  void _handleForegroundMessage(RemoteMessage message) {
    final senderID = message.data['senderID'];
    final senderUsername = message.data['senderUsername'] ?? 'Someone';
    final type = message.data['type'];

    // Treat post_share like a chat_message for notification stacking
    final isChat = type == 'chat_message' || type == 'post_share';

    // Don't show notification if we're already chatting with this person
    if (isChat && senderID != null && senderID == _activeChatUserId) {
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    // MessagingStyle logic for chat messages
    if (isChat && senderID != null) {
      // Get the raw message text
      final bodyText = notification.body ?? '';

      // Add message to history
      final messages = _messageHistory.putIfAbsent(senderID, () => []);
      messages.add(
        Message(
          bodyText,
          DateTime.now(),
          Person(
            name: senderUsername,
            key: senderID,
          ),
        ),
      );

      // Limit history to last 10 messages
      if (messages.length > 10) messages.removeAt(0);

      // Truncate the latest message to 50 chars for collapsed view
      final truncatedBody = bodyText.length > 50
          ? '${bodyText.substring(0, 50)}...'
          : bodyText;

      final messagingStyle = MessagingStyleInformation(
        Person(name: 'Me', key: 'me'),
        conversationTitle: senderUsername,
        messages: messages, // Already in chronological order (oldest first, newest last)
      );

      _localNotifications.show(
        senderID.hashCode,
        senderUsername,
        truncatedBody, // Shown when collapsed
        NotificationDetails(
          android: AndroidNotificationDetails(
            _chatChannel.id,
            _chatChannel.name,
            channelDescription: _chatChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: messagingStyle,
            groupKey: senderID,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    } else {
      // Non-chat notifications (standard)
      _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _chatChannel.id,
            _chatChannel.name,
            channelDescription: _chatChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  /// Handle notification tap when app is in background/foreground
  void _handleNotificationOpen(RemoteMessage message) {
    if (_onNotificationTap != null) {
      _onNotificationTap!(message.data);
    } else {
      _initialData = message.data;
    }
  }

  /// Handle tap on local notification (foreground notifications)
  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if (_onNotificationTap != null) {
        _onNotificationTap!(data);
      } else {
        _initialData = data;
      }
    } catch (e) {
      debugPrint('Error decoding notification payload: $e');
    }
  }
}
