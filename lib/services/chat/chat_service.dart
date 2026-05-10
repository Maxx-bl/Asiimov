import 'dart:async';
import 'dart:convert';

import 'package:asiimov/models/conversation.dart';
import 'package:asiimov/models/message.dart';
import 'package:asiimov/services/encryption/encryption_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:rxdart/rxdart.dart';

class ChatService extends ChangeNotifier {
  //get instance of firebase services
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;
  final EncryptionService encryption =
      EncryptionService(dotenv.env['ENCRYPTION_KEY'] ?? '');

  // Cached OAuth2 access token for FCM V1 API
  AccessCredentials? _cachedCredentials;

  //get all users stream
  Stream<List<Map<String, dynamic>>> getUsersStream() {
    return firestore.collection('users').snapshots().map((snapshot) {
      return snapshot.docs
          .where((doc) => doc.data()['email'] != auth.currentUser!.email)
          .map((doc) => doc.data())
          .toList();
    });
  }

  //get users stream except blocked users with limit
  Stream<List<Map<String, dynamic>>> getUsersStreamExcludingBlocked({int limit = 20}) {
    return firestore
        .collection('users')
        .doc(auth.currentUser!.uid)
        .collection('blockedUsers')
        .snapshots()
        .asyncMap((snapshot) async {
      final blockedUserIds = snapshot.docs.map((doc) => doc.id).toList();
      final usersSnapshot = await firestore.collection('users').limit(limit + blockedUserIds.length + 1).get();
      return usersSnapshot.docs
          .where((doc) =>
              doc.data()['email'] != auth.currentUser!.email &&
              !blockedUserIds.contains(doc.id))
          .map((doc) => doc.data())
          .take(limit)
          .toList();
    });
  }

  //get contacts stream except blocked users
  Stream<List<Map<String, dynamic>>> getContactsStreamExcludingBlocked() {
    final currentUser = auth.currentUser!;
    final currentUserId = currentUser.uid;

    final blockedStream = firestore
        .collection('users')
        .doc(currentUserId)
        .collection('blockedUsers')
        .snapshots();

    final chatStream = firestore.collection('chats').snapshots();

    // Combine les deux flux manuellement
    late StreamController<List<Map<String, dynamic>>> controller;
    List<String> currentBlockedIds = [];
    QuerySnapshot? currentChatsSnapshot;
    StreamSubscription? blockedSub;
    StreamSubscription? chatSub;

    void update() async {
      if (currentChatsSnapshot == null || controller.isClosed) return;

      final chatDocs = currentChatsSnapshot!.docs.toList();
      chatDocs.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>? ?? {};
        final bData = b.data() as Map<String, dynamic>? ?? {};
        final aTime = aData['updatedAt'] as Timestamp? ??
            aData['createdAt'] as Timestamp? ??
            Timestamp.fromMillisecondsSinceEpoch(0);
        final bTime = bData['updatedAt'] as Timestamp? ??
            bData['createdAt'] as Timestamp? ??
            Timestamp.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

      final orderedContactIds = <String>[];

      for (final doc in chatDocs) {
        final chatId = doc.id;
        final ids = chatId.split('_');
        if (ids.length != 2) continue;

        if (ids.contains(currentUserId)) {
          final otherUserId = ids.firstWhere((id) => id != currentUserId);
          if (!currentBlockedIds.contains(otherUserId) &&
              !orderedContactIds.contains(otherUserId)) {
            orderedContactIds.add(otherUserId);
          }
        }
      }

      if (orderedContactIds.isEmpty) {
        if (!controller.isClosed) controller.add([]);
        return;
      }

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: orderedContactIds)
          .get();

      final usersMap = {
        for (final doc in usersSnapshot.docs) doc.id: doc.data()
      };
      final orderedUsers = orderedContactIds
          .where((id) => usersMap.containsKey(id))
          .map((id) => usersMap[id]!)
          .toList();

      if (!controller.isClosed) controller.add(orderedUsers);
    }

    controller = StreamController<List<Map<String, dynamic>>>.broadcast(
      onListen: () {
        blockedSub = blockedStream.listen((blockedSnapshot) {
          currentBlockedIds =
              blockedSnapshot.docs.map((doc) => doc.id).toList();
          update();
        });

        chatSub = chatStream.listen((chatSnapshot) {
          currentChatsSnapshot = chatSnapshot;
          update();
        });
      },
      onCancel: () {
        blockedSub?.cancel();
        chatSub?.cancel();
        controller.close();
      },
    );

    return controller.stream;
  }

  //get information if user has new messages (Optimized with collectionGroup)
  Stream<Map<String, int>> getUnreadStatusForContacts() {
    final currentUserId = auth.currentUser!.uid;

    return firestore
        .collectionGroup('messages')
        .where('receiverID', isEqualTo: currentUserId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) {
      final Map<String, int> unreadStatus = {};
      for (final doc in snapshot.docs) {
        final senderID = doc['senderID'] as String;
        unreadStatus[senderID] = (unreadStatus[senderID] ?? 0) + 1;
      }
      return unreadStatus;
    });
  }

  // NEW: High-performance stream for the main conversation list
  Stream<List<Conversation>> getConversationsStream() {
    final currentUserId = auth.currentUser!.uid;

    // Stream 1: All chats I am part of
    final chatsStream = firestore
        .collection('chats')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .where((doc) => doc.id.contains(currentUserId))
            .toList());

    // Stream 2: Unread counts
    final unreadStream = getUnreadStatusForContacts();

    // Stream 3: All users (to avoid fetching each one separately)
    final usersStream = firestore.collection('users').snapshots();

    // Stream 4: Blocked users
    final blockedStream = firestore
        .collection('users')
        .doc(currentUserId)
        .collection('blockedUsers')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toList());

    return CombineLatestStream.combine4(
      chatsStream,
      unreadStream,
      usersStream,
      blockedStream,
      (chatDocs, unreadMap, usersSnapshot, blockedIds) {
        final usersMap = {
          for (final doc in usersSnapshot.docs) doc.id: doc.data()
        };

        final List<Conversation> conversations = [];

        for (final chatDoc in chatDocs) {
          final chatId = chatDoc.id;
          final ids = chatId.split('_');
          if (ids.length != 2) continue;

          final otherUserId = ids.firstWhere((id) => id != currentUserId);
          
          // Skip if blocked
          if (blockedIds.contains(otherUserId)) continue;

          final otherUserData = usersMap[otherUserId];
          if (otherUserData == null) continue;

          final chatData = chatDoc.data();
          final lastTimestamp = chatData['lastTimestamp'] as Timestamp? ?? 
                              chatData['updatedAt'] as Timestamp? ?? 
                              Timestamp.fromMillisecondsSinceEpoch(0);

          conversations.add(Conversation(
            userData: otherUserData,
            unreadCount: unreadMap[otherUserId] ?? 0,
            lastActive: lastTimestamp.toDate(),
            lastMessage: chatData['lastMessage'] != null ? {
              'message': chatData['lastMessage'],
              'senderID': chatData['lastSenderID'],
              'timestamp': chatData['lastTimestamp'],
            } : null,
          ));
        }

        // Sort by last active (newest first)
        conversations.sort((a, b) => b.lastActive.compareTo(a.lastActive));
        return conversations;
      },
    );
  }

  //send message
  Future<void> sendMessage(
    String receiverID,
    String message, {
    String? replyToMessageId,
    String? replyToMessage,
    String? replyToSenderID,
  }) async {
    //get current user info
    final String currentUserID = auth.currentUser!.uid;
    final String currentUserEmail = auth.currentUser!.email!;
    final Timestamp timestamp = Timestamp.now();
    final encryptedMessage = encryption.encrypt(message);

    // Encrypt reply preview if present
    final String? encryptedReply =
        replyToMessage != null ? encryption.encrypt(replyToMessage) : null;

    //create message
    Message newMessage = Message(
      senderID: currentUserID,
      senderEmail: currentUserEmail,
      receiverID: receiverID,
      message: encryptedMessage,
      timestamp: timestamp,
      isRead: false,
      replyToMessageId: replyToMessageId,
      replyToMessage: encryptedReply,
      replyToSenderID: replyToSenderID,
    );

    //create unique chat room ID
    List<String> ids = [currentUserID, receiverID];
    ids.sort();
    String chatRoomID = ids.join('_');

    //add to db
    await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .add(newMessage.toMap());

    await firestore
        .collection('chats')
        .doc(chatRoomID)
        .set({
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessage': encryptedMessage,
          'lastSenderID': currentUserID,
          'lastTimestamp': timestamp,
        }, SetOptions(merge: true));

    //send push notification to receiver
    // Get last 3 unread messages from current user to receiver for notification stacking
    final unreadSnapshot = await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .where('receiverID', isEqualTo: receiverID)
        .where('isRead', isEqualTo: false)
        .where('senderID', isEqualTo: currentUserID)
        .get();

    String notificationBody = message;
    if (unreadSnapshot.docs.length > 1) {
      // Sort in memory to avoid needing a composite index in Firestore
      final docs = unreadSnapshot.docs.toList();
      docs.sort((a, b) {
        final aTime = a.data()['timestamp'] as Timestamp? ?? Timestamp.now();
        final bTime = b.data()['timestamp'] as Timestamp? ?? Timestamp.now();
        return bTime.compareTo(aTime); // Descending
      });

      final latest3 = docs.take(3).toList();
      final unreadTexts = latest3.map((doc) {
        final data = doc.data();
        try {
          return encryption.decrypt(data['message']);
        } catch (e) {
          return "New message";
        }
      }).toList();

      // Join with newlines, newest at the bottom
      notificationBody = unreadTexts.reversed.join('\n');
    }

    await sendPushNotification(receiverID, notificationBody);
  }

  //add or toggle reaction on a message
  Future<void> addReaction(
      String otherUserId, String messageDocId, String emoji) async {
    final currentUserId = auth.currentUser!.uid;

    List<String> ids = [currentUserId, otherUserId];
    ids.sort();
    String chatRoomID = ids.join('_');

    final docRef = firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .doc(messageDocId);

    final doc = await docRef.get();
    final data = doc.data();
    if (data == null) return;

    final reactions =
        Map<String, String>.from(data['reactions'] as Map? ?? {});

    // Toggle: if same emoji, remove it; otherwise set new one
    if (reactions[currentUserId] == emoji) {
      reactions.remove(currentUserId);
    } else {
      reactions[currentUserId] = emoji;
    }

    await docRef.update({'reactions': reactions});

    // Send notification if adding a reaction (not removing)
    if (reactions.containsKey(currentUserId)) {
      final messageOwnerID = data['senderID'] as String;
      // Only notify if reacting to someone else's message
      if (messageOwnerID != currentUserId) {

        await sendPushNotification(
            messageOwnerID, 'reacted $emoji to your message');
      }
    }
  }

  //remove reaction from a message
  Future<void> removeReaction(String otherUserId, String messageDocId) async {
    final currentUserId = auth.currentUser!.uid;

    List<String> ids = [currentUserId, otherUserId];
    ids.sort();
    String chatRoomID = ids.join('_');

    await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .doc(messageDocId)
        .update({'reactions.$currentUserId': FieldValue.delete()});
  }

  //send push notification via FCM V1 API
  Future<void> sendPushNotification(String receiverID, String messageText,
      {String? title, String? type, Map<String, dynamic>? extraData}) async {
    try {
      //get receiver's FCM token
      final receiverDoc =
          await firestore.collection('users').doc(receiverID).get();
      final receiverData = receiverDoc.data();
      if (receiverData == null) return;

      final fcmToken = receiverData['fcmToken'];
      if (fcmToken == null || fcmToken.isEmpty) return;

      //get sender's username
      final senderUsername = auth.currentUser?.displayName ?? 'Someone';

      //truncate message preview (increased for stacked messages)
      final preview = messageText.length > 200
          ? '${messageText.substring(0, 200)}...'
          : messageText;

      //get OAuth2 access token
      final accessToken = await _getAccessToken();
      if (accessToken == null) return;

      final notificationType = type ?? 'chat_message';

      // Use senderID as tag for chats to stack/replace.
      // For others, use unique tag (timestamp) to keep them separate.
      final String tag = notificationType == 'chat_message'
          ? auth.currentUser!.uid
          : DateTime.now().millisecondsSinceEpoch.toString();

      //send notification via FCM V1 API
      final response = await http.post(
        Uri.parse(
            'https://fcm.googleapis.com/v1/projects/asiimov-b3792/messages:send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'message': {
            'token': fcmToken,
            'notification': {
              'title': title ?? senderUsername,
              'body': preview,
            },
            'data': {
              'senderID': auth.currentUser!.uid.toString(),
              'senderUsername': senderUsername.toString(),
              'type': notificationType.toString(),
              if (extraData != null)
                ...extraData
                    .map((key, value) => MapEntry(key, value.toString())),
            },
            'android': {
              'notification': {
                'channel_id': 'chat_messages',
                'tag': tag,
              },
            },
          },
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('FCM error: ${response.statusCode} - ${response.body}');
      } else {
        debugPrint('Notification sent successfully');
      }
    } catch (e) {
      debugPrint('Error sending push notification: $e');
    }
  }

  //get OAuth2 access token from service account
  Future<String?> _getAccessToken() async {
    try {
      // Return cached token if still valid
      if (_cachedCredentials != null &&
          _cachedCredentials!.accessToken.expiry
              .isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
        return _cachedCredentials!.accessToken.data;
      }

      // Load service account JSON from assets
      final serviceAccountJson =
          await rootBundle.loadString('assets/service-account.json');
      final credentials =
          ServiceAccountCredentials.fromJson(serviceAccountJson);

      // Get access token with FCM scope
      final client = http.Client();
      _cachedCredentials = await obtainAccessCredentialsViaServiceAccount(
        credentials,
        ['https://www.googleapis.com/auth/firebase.messaging'],
        client,
      );
      client.close();

      return _cachedCredentials?.accessToken.data;
    } catch (e) {
      debugPrint('Error getting FCM access token: $e');
      return null;
    }
  }

  //get messages
  Stream<QuerySnapshot> getMessages(String userID, String otherUserID) {
    //construct chat room ID from user IDs (sorted to ensure it is the same for both users)
    List<String> ids = [userID, otherUserID];
    ids.sort();
    String chatRoomID = ids.join('_');

    return firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  //get messages with limit (Added back as helper if needed, but not used by simple getMessages)
  Stream<QuerySnapshot> getMessagesWithLimit(String userID, String otherUserID, int limit) {
    List<String> ids = [userID, otherUserID];
    ids.sort();
    String chatRoomID = ids.join('_');

    return firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  //get older messages as a future (pagination)
  Future<QuerySnapshot> getOldMessagesFuture(String userID, String otherUserID, DocumentSnapshot lastDoc, int limit) {
    List<String> ids = [userID, otherUserID];
    ids.sort();
    String chatRoomID = ids.join('_');

    return firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .startAfterDocument(lastDoc)
        .limit(limit)
        .get();
  }

  //get last message for a conversation
  Stream<DocumentSnapshot?> getLastMessageStream(String otherUserId) {
    final currentUserId = auth.currentUser!.uid;
    List<String> ids = [currentUserId, otherUserId];
    ids.sort();
    String chatRoomID = ids.join('_');

    return firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) => snapshot.docs.isNotEmpty ? snapshot.docs.first : null);
  }

  //mark messages as read
  void markMessagesAsRead(String otherUserId) async {
    final currentUserId = auth.currentUser?.uid;

    List<String> ids = [currentUserId ?? '', otherUserId];
    ids.sort();
    String chatRoomID = ids.join('_');

    final unreadMessagesSnapshot = await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .where('receiverID', isEqualTo: currentUserId)
        .where('isRead', isEqualTo: false)
        .get();

    for (final doc in unreadMessagesSnapshot.docs) {
      await doc.reference.update({'isRead': true});
    }
  }

  //delete old messages
  Future<void> cleanUpOldMessages(String otherUserId) async {
    final currentUserId = auth.currentUser?.uid;

    List<String> ids = [currentUserId ?? '', otherUserId];
    ids.sort();
    String chatRoomID = ids.join('_');

    final messagesSnapshot = await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .get();

    final messages = messagesSnapshot.docs;

    if (messages.length > 20) {
      final toDelete = messages.take(messages.length - 20);
      for (final doc in toDelete) {
        await doc.reference.delete();
      }
      return;
    }

    final now = DateTime.now();
    for (final doc in messages) {
      final data = doc.data();
      final isRead = data['isRead'] ?? false;
      final timestamp = (data['timestamp'] as Timestamp).toDate();

      final isOlderThan24h = now.difference(timestamp).inHours >= 24;

      if (isRead && isOlderThan24h) {
        await doc.reference.delete();
      }
    }
  }

  //report user
  Future<void> reportUser(String messageId, String userId) async {
    final currentUser = auth.currentUser;
    final report = {
      'reportedBy': currentUser!.uid,
      'messageId': messageId,
      'messageOwnerId': userId,
      'timestamp': FieldValue.serverTimestamp(),
    };

    await firestore.collection('reports').add(report);
  }

  //block user
  Future<void> blockUser(String userId) async {
    final currentUser = auth.currentUser;
    await firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('blockedUsers')
        .doc(userId)
        .set({});
    notifyListeners();
  }

  //unblock user
  Future<void> unblockUser(String blockedUserId) async {
    final currentUser = auth.currentUser;
    await firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('blockedUsers')
        .doc(blockedUserId)
        .delete();
  }

  //get blocked users stream
  Stream<List<Map<String, dynamic>>> getBlockedUsersStream(String userId) {
    return firestore
        .collection('users')
        .doc(userId)
        .collection('blockedUsers')
        .snapshots()
        .asyncMap((snapshot) async {
      final blockedUserIds = snapshot.docs.map((doc) => doc.id).toList();
      final userDocs = await Future.wait(blockedUserIds
          .map((id) => firestore.collection('users').doc(id).get()));
      return userDocs.map((doc) => doc.data() as Map<String, dynamic>).toList();
    });
  }

  //delete message
  Future<void> deleteMessage(String otherUserId, String messageId) async {
    final currentUserId = auth.currentUser!.uid;

    List<String> ids = [currentUserId, otherUserId];
    ids.sort();
    String chatRoomID = ids.join('_');

    await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .doc(messageId)
        .delete();
  }
}
