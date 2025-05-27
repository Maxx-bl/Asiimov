import 'dart:async';

import 'package:asiimov/models/message.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatService extends ChangeNotifier {
  //get instance of firebase services
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

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
      Map<String, bool> unreadStatus = {};

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
  Future<void> sendMessage(String receiverID, message) async {
    //get current user info
    final String currentUserID = auth.currentUser!.uid;
    final String currentUserEmail = auth.currentUser!.email!;
    final Timestamp timestamp = Timestamp.now();

    //create message
    Message newMessage = Message(
      senderID: currentUserID,
      senderEmail: currentUserEmail,
      receiverID: receiverID,
      message: message,
      timestamp: timestamp,
      isRead: false,
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
  }

  //get messages
  Stream<QuerySnapshot> getMessages(String userID, otherUserID) {
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
