import 'dart:async';
import 'dart:convert';

import 'package:asiimov/models/message.dart';
import 'package:asiimov/services/encryption/encryption_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

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

  //get users stream except blocked users
  Stream<List<Map<String, dynamic>>> getUsersStreamExcludingBlocked() {
    return firestore
        .collection('users')
        .doc(auth.currentUser!.uid)
        .collection('blockedUsers')
        .snapshots()
        .asyncMap((snapshot) async {
      final blockedUserIds = snapshot.docs.map((doc) => doc.id).toList();
      final usersSnapshot = await firestore.collection('users').get();
      return usersSnapshot.docs
          .where((doc) =>
              doc.data()['email'] != auth.currentUser!.email &&
              !blockedUserIds.contains(doc.id))
          .map((doc) => doc.data())
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

    void update() async {
      if (currentChatsSnapshot == null) return;

      final contactIds = <String>{};

      for (final doc in currentChatsSnapshot!.docs) {
        final chatId = doc.id;
        final ids = chatId.split('_');
        if (ids.length != 2) continue;

        if (ids.contains(currentUserId)) {
          final otherUserId = ids.firstWhere((id) => id != currentUserId);
          if (!currentBlockedIds.contains(otherUserId)) {
            contactIds.add(otherUserId);
          }
        }
      }

      if (contactIds.isEmpty) {
        controller.add([]);
        return;
      }

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: contactIds.toList())
          .get();

      controller.add(usersSnapshot.docs.map((doc) => doc.data()).toList());
    }

    controller = StreamController<List<Map<String, dynamic>>>.broadcast(
      onListen: () {
        blockedStream.listen((blockedSnapshot) {
          currentBlockedIds =
              blockedSnapshot.docs.map((doc) => doc.id).toList();
          update();
        });

        chatStream.listen((chatSnapshot) {
          currentChatsSnapshot = chatSnapshot;
          update();
        });
      },
      onCancel: () {
        controller.close();
      },
    );

    return controller.stream;
  }

  //get information if user has new messages
  Stream<Map<String, bool>> getUnreadStatusForContacts() {
    final currentUserId = auth.currentUser!.uid;

    return firestore
        .collection('chats')
        .snapshots()
        .asyncMap((chatSnapshot) async {
      final Map<String, bool> unreadStatus = {};

      for (final chatDoc in chatSnapshot.docs) {
        final chatId = chatDoc.id;
        final ids = chatId.split('_');
        if (!ids.contains(currentUserId)) continue;

        final otherUserId = ids.firstWhere((id) => id != currentUserId);

        final unreadMessages = await firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .where('receiverID', isEqualTo: currentUserId)
            .where('isRead', isEqualTo: false)
            .limit(1)
            .get();

        unreadStatus[otherUserId] = unreadMessages.docs.isNotEmpty;
      }

      return unreadStatus;
    });
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
        .set({'createdAt': FieldValue.serverTimestamp()});

    //send push notification to receiver
    await sendPushNotification(receiverID, message);
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
        final senderUsername = auth.currentUser?.displayName ?? 'Someone';
        await sendPushNotification(
            messageOwnerID, '$emoji $senderUsername reacted');
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
  Future<void> sendPushNotification(String receiverID, String messageText, {String? title, String? type}) async {
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

      //truncate message preview
      final preview = messageText.length > 50
          ? '${messageText.substring(0, 50)}...'
          : messageText;

      //get OAuth2 access token
      final accessToken = await _getAccessToken();
      if (accessToken == null) return;

      //send notification via FCM V1 API
      await http.post(
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
              'senderID': auth.currentUser!.uid,
              'senderUsername': senderUsername,
              'type': type ?? 'chat_message',
            },
            'android': {
              'notification': {
                'channel_id': 'chat_messages',
                'tag': auth.currentUser!.uid,
              },
            },
          },
        }),
      );
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
    //construct chatroom ID
    List<String> ids = [userID, otherUserID];
    ids.sort();
    String chatRoomID = ids.join('_');

    return firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
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
}
