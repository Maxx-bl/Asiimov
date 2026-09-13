import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Android notification channel for chat messages
const AndroidNotificationChannel _chatChannel = AndroidNotificationChannel(
  'chat_messages',
  'Chat Messages',
  description: 'Notifications for new chat messages',
  importance: Importance.high,
  playSound: true,
);

const Color _notificationColor = Color(0xFFA8C4D8);

/// How many past messages are kept (and shown, expanded) per conversation.
const int _maxHistoryLength = 4;

/// A single message kept in a conversation's persisted notification history.
class _StoredMessage {
  final String text;
  final int timestampMs;
  final String senderName;
  final String senderKey;
  /// Firestore message id, used to find and update this entry in place when
  /// the sender edits the message instead of appending a new one.
  final String? messageId;

  _StoredMessage(
      this.text, this.timestampMs, this.senderName, this.senderKey, this.messageId);

  Map<String, dynamic> toJson() => {
        'text': text,
        'ts': timestampMs,
        'name': senderName,
        'key': senderKey,
        'msgId': messageId,
      };

  factory _StoredMessage.fromJson(Map<String, dynamic> json) => _StoredMessage(
        json['text'] as String,
        json['ts'] as int,
        json['name'] as String,
        json['key'] as String,
        json['msgId'] as String?,
      );
}

String _historyPrefsKey(String conversationKey) =>
    'chat_notif_history_$conversationKey';

Future<List<_StoredMessage>> _loadMessageHistory(String conversationKey) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_historyPrefsKey(conversationKey));
  if (raw == null) return [];
  try {
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => _StoredMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (e) {
    debugPrint('Error decoding notification history: $e');
    return [];
  }
}

Future<void> _saveMessageHistory(
    String conversationKey, List<_StoredMessage> messages) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    _historyPrefsKey(conversationKey),
    jsonEncode(messages.map((m) => m.toJson()).toList()),
  );
}

/// Clear the persisted message history for a conversation (called when the
/// user opens it, so the next message starts a fresh notification).
Future<void> _clearMessageHistory(String conversationKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_historyPrefsKey(conversationKey));
}

/// Build and show a single collapsing MessagingStyle notification per
/// conversation (Instagram-style stacking), backed by history persisted to
/// disk so it works the same whether the app is foregrounded, backgrounded,
/// or fully killed (each of which may run this in a different isolate).
Future<void> _showChatMessageNotification(Map<String, dynamic> data) async {
  final senderID = data['senderID'] as String?;
  if (senderID == null) return;

  final senderUsername = (data['senderUsername'] as String?) ?? 'Someone';
  final isGroup = data['isGroup'] == 'true';
  final groupName = data['groupName'] as String?;
  final rawBody = (data['body'] as String?) ?? '';

  final displayTitle =
      (isGroup && groupName != null && groupName.isNotEmpty) ? groupName : senderUsername;
  final String conversationKey =
      isGroup ? ((data['groupId'] as String?) ?? senderID) : senderID;

  // Group message bodies arrive as "Username: text" — strip that prefix
  // since MessagingStyle already attributes each line to its sender.
  String cleanBodyText = rawBody;
  if (isGroup) {
    cleanBodyText = rawBody.replaceFirst(RegExp(r'^.*?: '), '');
    if (cleanBodyText == rawBody && rawBody.contains(': ')) {
      cleanBodyText = rawBody.split(': ').sublist(1).join(': ');
    }
  }

  final messageId = data['messageId'] as String?;
  final isEdit = data['isEdit'] == 'true';

  final history = await _loadMessageHistory(conversationKey);

  bool isSilentUpdate = false;
  if (isEdit && messageId != null) {
    final idx = history.indexWhere((m) => m.messageId == messageId);
    if (idx == -1) {
      // Nothing currently showing for this message (already read/dismissed)
      // — don't surface the edit as a fresh alert.
      return;
    }
    history[idx] = _StoredMessage(
      cleanBodyText,
      history[idx].timestampMs,
      senderUsername,
      senderID,
      messageId,
    );
    isSilentUpdate = true;
  } else if (history.isEmpty ||
      history.last.text != cleanBodyText ||
      history.last.messageId != messageId) {
    history.add(_StoredMessage(
      cleanBodyText,
      DateTime.now().millisecondsSinceEpoch,
      senderUsername,
      senderID,
      messageId,
    ));
  }
  if (history.length > _maxHistoryLength) {
    history.removeAt(0);
  }
  await _saveMessageHistory(conversationKey, history);

  final messages = history
      .map((m) => Message(
            m.text,
            DateTime.fromMillisecondsSinceEpoch(m.timestampMs),
            Person(name: m.senderName, key: m.senderKey),
          ))
      .toList();

  final messagingStyle = MessagingStyleInformation(
    Person(name: 'Me', key: 'me'),
    conversationTitle: displayTitle,
    groupConversation: isGroup,
    messages: messages,
  );

  final localNotifications = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
  await localNotifications.initialize(
    const InitializationSettings(android: androidSettings),
  );
  await localNotifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_chatChannel);

  await localNotifications.show(
    conversationKey.hashCode,
    displayTitle,
    isGroup ? "$senderUsername: $cleanBodyText" : cleanBodyText,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _chatChannel.id,
        _chatChannel.name,
        channelDescription: _chatChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: messagingStyle,
        groupKey: conversationKey,
        color: _notificationColor,
        colorized: true,
        ticker: rawBody,
        // An edit just corrects text already shown — don't re-alert for it.
        playSound: !isSilentUpdate,
        enableVibration: !isSilentUpdate,
      ),
    ),
    payload: jsonEncode(data),
  );
}

/// Top-level background message handler (must be top-level function).
/// Runs in its own isolate with no shared state — chat messages are shown
/// here directly (backed by the persisted history above) so background and
/// foreground notifications stack identically.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background message received: ${message.messageId}');
  if (message.data['type'] == 'chat_message') {
    await _showChatMessageNotification(message.data);
  }
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

  /// Initialize the notification service
  Future<void> initialize() async {
    // Request permissions
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Initialize local notifications plugin FIRST (required before resolvePlatformSpecificImplementation)
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');

    const initSettings = InitializationSettings(android: androidSettings);

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create the Android notification channel AFTER initialization
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_chatChannel);

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

    // Check if app was opened from a terminated state via an FCM-displayed
    // notification (follow/comment/etc — still auto-displayed by FCM).
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationOpen(initialMessage);
    }

    // Chat notifications are shown by us (flutter_local_notifications), not
    // auto-displayed by FCM, so a cold start from tapping one does NOT fire
    // onDidReceiveNotificationResponse on Android — it must be read here.
    final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails!.notificationResponse?.payload;
      if (payload != null) _deliverTapPayload(payload);
    }
  }

  /// Set the active chat user and clear their notifications
  void setActiveChatUser(String? userId) {
    _activeChatUserId = userId;
    if (userId != null) {
      clearNotificationsForUser(userId);
    }
  }

  /// Clear all notifications from a specific conversation (local + FCM background).
  Future<void> clearNotificationsForUser(String userId) async {
    await _clearMessageHistory(userId);

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    // Cancel local notification by integer ID (foreground-shown)
    await androidPlugin.cancel(userId.hashCode);

    // Cancel any lingering FCM-managed notifications for this conversation
    // (e.g. from before this fix, or other tagged pushes). The server tags
    // non-chat pushes as "<tag>::<unique>" so match by prefix here too.
    try {
      final activeNotifs = await androidPlugin.getActiveNotifications();
      for (final notif in activeNotifs) {
        final tag = notif.tag;
        if (tag == userId ||
            (tag?.startsWith('$userId::') ?? false) ||
            notif.id == userId.hashCode) {
          await androidPlugin.cancel(notif.id ?? 0, tag: notif.tag);
        }
      }
    } catch (e) {
      debugPrint('getActiveNotifications error: $e');
    }
  }

  /// Cancel a single notification by (id, tag) — used for follow/comment notifs.
  Future<void> cancelNotification(int id, {String? tag}) async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;
    await androidPlugin.cancel(id, tag: tag);
    // Also scan active notifications to catch FCM-managed ones with matching
    // tag — the server appends "::<unique>" to its tag so pushes stack
    // instead of replacing each other, so match by prefix too.
    if (tag != null) {
      try {
        final activeNotifs = await androidPlugin.getActiveNotifications();
        for (final notif in activeNotifs) {
          final notifTag = notif.tag;
          if (notifTag == tag || (notifTag?.startsWith('$tag::') ?? false)) {
            await androidPlugin.cancel(notif.id ?? 0, tag: notif.tag);
          }
        }
      } catch (e) {
        debugPrint('getActiveNotifications error: $e');
      }
    }
  }

  /// Handle foreground messages — show notification unless we're in that conversation
  void _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;
    final senderID = data['senderID'];
    final type = data['type'];
    final isGroup = data['isGroup'] == 'true';

    // Everything except social notifications is a conversation message → stack it
    const socialTypes = {'follow', 'follow_request', 'follow_accept', 'comment'};
    final isChat = senderID != null && !socialTypes.contains(type);

    if (isChat) {
      // Don't show notification if we're already chatting with this person or group
      final chatTargetID = isGroup ? data['groupId'] : senderID;
      if (chatTargetID != null && chatTargetID == _activeChatUserId) {
        return;
      }
      await _showChatMessageNotification(data);
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    // Non-chat notifications: use stable IDs so they can be cancelled on tap.
    // follow/follow_request/follow_accept → group by sender (one notif per person)
    // comment → group by post path
    int notifId;
    String? notifTag;
    if (type == 'follow' || type == 'follow_request' || type == 'follow_accept') {
      notifId = senderID?.hashCode ?? DateTime.now().millisecondsSinceEpoch.hashCode;
      notifTag = 'follow_$senderID';
    } else if (type == 'comment') {
      final parentPath = data['parentPath'] ?? data['postId'];
      notifId = parentPath?.hashCode ?? DateTime.now().millisecondsSinceEpoch.hashCode;
      notifTag = 'comment_$parentPath';
    } else {
      notifId = DateTime.now().millisecondsSinceEpoch.hashCode;
    }

    _localNotifications.show(
      notifId,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _chatChannel.id,
          _chatChannel.name,
          channelDescription: _chatChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          color: _notificationColor,
          colorized: true,
          tag: notifTag,
        ),
      ),
      payload: jsonEncode(data),
    );
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
    _deliverTapPayload(payload);
  }

  /// Decode a notification payload and route it to the tap handler (or stash
  /// it for when one is registered).
  void _deliverTapPayload(String payload) {
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
