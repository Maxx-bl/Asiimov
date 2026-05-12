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

    return Rx.combineLatest2(
      firestore
          .collectionGroup('messages')
          .where('receiverID', isEqualTo: currentUserId)
          .where('isRead', isEqualTo: false)
          .snapshots(),
      firestore
          .collectionGroup('messages')
          .where('unreadBy', arrayContains: currentUserId)
          .snapshots(),
      (QuerySnapshot private, QuerySnapshot groups) {
        final Map<String, int> unreadStatus = {};
        
        for (final doc in private.docs) {
          final senderID = doc['senderID'] as String;
          unreadStatus[senderID] = (unreadStatus[senderID] ?? 0) + 1;
        }
        
        for (final doc in groups.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final receiverID = data['receiverID'] as String; // This is the groupId
          unreadStatus[receiverID] = (unreadStatus[receiverID] ?? 0) + 1;
        }
        
        return unreadStatus;
      }
    ).handleError((error) {
      debugPrint("❌ FIRESTORE INDEX ERROR: $error");
    });
  }

  // NEW: High-performance stream for the main conversation list
  Stream<List<Conversation>> getConversationsStream() {
    final currentUserId = auth.currentUser!.uid;

    // Stream 1: All chats I am part of (including groups)
    final chatsStream = firestore
        .collection('chats')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .where((doc) {
              final data = doc.data();
              if (data['type'] == 'group') {
                final members = List<String>.from(data['members'] ?? []);
                return members.contains(currentUserId);
              }
              return doc.id.contains(currentUserId);
            })
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
          final chatData = chatDoc.data();
          
          final isGroup = chatData['type'] == 'group';
          String otherUserId;
          
          if (isGroup) {
            otherUserId = chatId;
          } else {
            final ids = chatId.split('_');
            if (ids.length < 2) continue; // Skip malformed private chats
            otherUserId = ids.firstWhere((id) => id != currentUserId, orElse: () => ids.first);
          }

          if (otherUserId.isEmpty) continue;
          
          // Skip if blocked (only for private chats)
          if (!isGroup && blockedIds.contains(otherUserId)) continue;

          final otherUserData = isGroup ? <String, dynamic>{} : usersMap[otherUserId];
          if (!isGroup && otherUserData == null) continue;

          final lastTimestamp = chatData['lastTimestamp'] as Timestamp? ?? 
                              chatData['updatedAt'] as Timestamp? ?? 
                              Timestamp.fromMillisecondsSinceEpoch(0);

          conversations.add(Conversation(
            id: otherUserId,
            userData: otherUserData ?? {},
            unreadCount: unreadMap[isGroup ? chatId : otherUserId] ?? 0,
            lastActive: lastTimestamp.toDate(),
            isGroup: isGroup,
            groupName: chatData['groupName'],
            members: isGroup ? List<String>.from(chatData['members'] ?? []) : null,
            creatorId: chatData['creatorId'],
            lastMessage: chatData['lastMessage'] != null ? {
              'message': chatData['lastMessage'],
              'senderID': chatData['lastSenderID'],
              'senderUsername': chatData['lastSenderUsername'],
              'timestamp': chatData['lastTimestamp'],
              'isRead': chatData['lastMessageRead'] ?? false,
              'isSystemMessage': chatData['lastIsSystem'] ?? false,
            } : null,
          ));
        }

        // Sort by last active (newest first)
        conversations.sort((a, b) => b.lastActive.compareTo(a.lastActive));
        return conversations;
      },
    );
  }

  // NEW: Create a new group discussion
  Future<String> createGroup(String name, List<String> memberIds) async {
    final currentUserId = auth.currentUser!.uid;
    final currentUsername = auth.currentUser?.displayName ?? 'Someone';
    
    // Add current user to members
    final allMembers = [currentUserId, ...memberIds];
    
    // Create member details with join timestamps
    final memberDetails = {
      for (var id in allMembers) id: FieldValue.serverTimestamp()
    };

    // Generate unique ID for the group
    final chatRoomID = 'group_${DateTime.now().millisecondsSinceEpoch}_$currentUserId';

    final groupData = {
      'type': 'group',
      'groupName': name,
      'creatorId': currentUserId,
      'members': allMembers,
      'memberDetails': memberDetails,
      'mutedBy': [],
      'lastMessage': '',
      'lastSenderID': '',
      'lastSenderUsername': '',
      'lastTimestamp': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await firestore.collection('chats').doc(chatRoomID).set(groupData);

    // Initial system message
    String content;
    if (memberIds.isEmpty) {
      content = "$currentUsername created the group \"$name\"";
    } else {
      // Fetch usernames for the added members
      final usersSnap = await firestore.collection('users').where(FieldPath.documentId, whereIn: memberIds).get();
      final usernames = usersSnap.docs.map((doc) => doc.data()['username'] ?? 'Unknown').toList();
      content = "$currentUsername added ${usernames.join(', ')}";
    }
    
    await sendSystemMessage(chatRoomID, content);

    return chatRoomID;
  }

  // NEW: Send a system message (info message in the center)
  Future<void> sendSystemMessage(String chatRoomID, String content) async {
    final timestamp = Timestamp.now();
    
    final messageData = {
      'senderID': 'system',
      'message': content, // Not encrypted for system messages
      'timestamp': timestamp,
      'isRead': true,
      'isSystemMessage': true,
    };

    await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .add(messageData);

    // Update conversation metadata
    await firestore.collection('chats').doc(chatRoomID).update({
      'lastMessage': content,
      'lastSenderID': 'system',
      'lastSenderUsername': 'System',
      'lastTimestamp': timestamp,
      'lastIsSystem': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // NEW: Rename a group
  Future<void> renameGroup(String groupId, String newName) async {
    final currentUsername = auth.currentUser?.displayName ?? 'Someone';
    await firestore.collection('chats').doc(groupId).update({
      'groupName': newName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await sendSystemMessage(groupId, "$currentUsername renamed the group to \"$newName\"");
  }

  // NEW: Toggle mute for a group
  Future<void> toggleMuteGroup(String groupId, bool mute) async {
    final currentUserId = auth.currentUser!.uid;
    if (mute) {
      await firestore.collection('chats').doc(groupId).update({
        'mutedBy': FieldValue.arrayUnion([currentUserId]),
      });
    } else {
      await firestore.collection('chats').doc(groupId).update({
        'mutedBy': FieldValue.arrayRemove([currentUserId]),
      });
    }
  }

  // NEW: Update group members (Add/Remove)
  Future<void> updateGroupMembers(String groupId, List<String> newMemberIds) async {
    final currentUserId = auth.currentUser!.uid;
    final currentUsername = auth.currentUser?.displayName ?? 'Someone';
    
    final groupDoc = await firestore.collection('chats').doc(groupId).get();
    final oldMembers = List<String>.from(groupDoc.data()?['members'] ?? []);
    
    // Find who was added and who was removed
    final added = newMemberIds.where((id) => !oldMembers.contains(id)).toList();
    final removed = oldMembers.where((id) => !newMemberIds.contains(id) && id != currentUserId).toList();

    if (added.isEmpty && removed.isEmpty) return;

    // Build update map for memberDetails
    final Map<String, dynamic> memberDetailsUpdate = {};
    for (var id in added) {
      memberDetailsUpdate['memberDetails.$id'] = FieldValue.serverTimestamp();
    }
    for (var id in removed) {
      memberDetailsUpdate['memberDetails.$id'] = FieldValue.delete();
    }

    await firestore.collection('chats').doc(groupId).update({
      'members': [currentUserId, ...newMemberIds],
      ...memberDetailsUpdate,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Send system messages
    if (added.isNotEmpty) {
      final usersSnap = await firestore.collection('users').where(FieldPath.documentId, whereIn: added).get();
      final usernames = usersSnap.docs.map((doc) => doc.data()['username'] ?? 'Unknown').toList();
      await sendSystemMessage(groupId, "$currentUsername added ${usernames.join(', ')}");
    }
    if (removed.isNotEmpty) {
      final usersSnap = await firestore.collection('users').where(FieldPath.documentId, whereIn: removed).get();
      final usernames = usersSnap.docs.map((doc) => doc.data()['username'] ?? 'Unknown').toList();
      await sendSystemMessage(groupId, "$currentUsername removed ${usernames.join(', ')}");
    }
  }

  // NEW: Leave a group with admin succession logic
  Future<void> leaveGroup(String groupId) async {
    final currentUserId = auth.currentUser!.uid;
    final currentUsername = auth.currentUser?.displayName ?? 'Someone';
    
    final groupDoc = await firestore.collection('chats').doc(groupId).get();
    final data = groupDoc.data();
    if (data == null) return;

    final List<String> members = List<String>.from(data['members'] ?? []);
    final String creatorId = data['creatorId'] ?? '';
    final Map<String, dynamic> memberDetails = Map<String, dynamic>.from(data['memberDetails'] ?? {});

    // 1. Remove me from members and details
    members.remove(currentUserId);
    memberDetails.remove(currentUserId);

    if (members.isEmpty) {
      // Last person left, delete the chat or just mark as inactive
      await firestore.collection('chats').doc(groupId).delete();
      return;
    }

    final updates = {
      'members': members,
      'memberDetails': memberDetails,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // 2. If I was the creator, find the oldest member
    if (currentUserId == creatorId) {
      String? nextAdmin;
      Timestamp? oldestTimestamp;

      memberDetails.forEach((uid, timestamp) {
        if (timestamp is Timestamp) {
          if (oldestTimestamp == null || timestamp.compareTo(oldestTimestamp!) < 0) {
            oldestTimestamp = timestamp;
            nextAdmin = uid;
          }
        }
      });

      // If no timestamp found, pick the first member
      nextAdmin ??= members.first;
      
      updates['creatorId'] = nextAdmin ?? members.first;
      
      // Fetch new admin username
      final adminDoc = await firestore.collection('users').doc(nextAdmin).get();
      final adminUsername = adminDoc.data()?['username'] ?? 'Someone';
      
      await sendSystemMessage(groupId, "$currentUsername left the group. $adminUsername is the new admin.");
    } else {
      await sendSystemMessage(groupId, "$currentUsername left the group.");
    }

    await firestore.collection('chats').doc(groupId).update(updates);
  }

  //send message
  Future<void> sendMessage(String receiverID, String message,
      {bool isGroup = false,
      String? replyToMessageId,
      String? replyToMessage,
      String? replyToSenderID,
      String messageType = 'text',
      String? sharedPostId}) async {
    //get current user info
    final String currentUserId = auth.currentUser!.uid;
    final String currentUserEmail = auth.currentUser!.email!;
    final Timestamp timestamp = Timestamp.now();

    //encrypt the message
    final String encryptedMessage = encryption.encrypt(message);

    //create a new message
    Message newMessage = Message(
      senderID: currentUserId,
      senderEmail: currentUserEmail,
      receiverID: receiverID,
      message: encryptedMessage,
      timestamp: timestamp,
      isRead: false,
      messageType: messageType,
      sharedPostId: sharedPostId,
      replyToMessageId: replyToMessageId,
      replyToMessage: replyToMessage,
      replyToSenderID: replyToSenderID,
    );

    // For group unread tracking
    List<String> unreadBy = [];
    if (isGroup) {
      final groupDoc = await firestore.collection('chats').doc(receiverID).get();
      final List<String> members = List<String>.from(groupDoc.data()?['members'] ?? []);
      unreadBy = members.where((id) => id != currentUserId).toList();
    }

    // Construct chat room ID
    String chatRoomID;
    if (isGroup) {
      chatRoomID = receiverID; // For groups, receiverID is the groupId
    } else {
      List<String> ids = [currentUserId, receiverID];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    //add to db
    final messageMap = newMessage.toMap();
    messageMap['senderUsername'] = auth.currentUser?.displayName ?? 'Someone';
    if (isGroup) {
      messageMap['unreadBy'] = unreadBy;
    }
    
    await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .add(messageMap);

    // Update conversation metadata
    final updateData = {
      'lastMessage': encryptedMessage,
      'lastSenderID': currentUserId,
      'lastSenderUsername': auth.currentUser?.displayName ?? 'Someone',
      'lastTimestamp': timestamp,
      'lastMessageRead': false,
      'lastIsSystem': false,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // For groups, we don't want to overwrite the whole doc, just merge metadata
    await firestore.collection('chats').doc(chatRoomID).set(updateData, SetOptions(merge: true));
    
    // For private chats, we ensure users list exists (groups set it at creation)
    if (!isGroup) {
      final List<String> ids = [currentUserId, receiverID];
      ids.sort();
      await firestore.collection('chats').doc(chatRoomID).update({
        'users': ids,
      }).catchError((_) => firestore.collection('chats').doc(chatRoomID).set({'users': ids}, SetOptions(merge: true)));
    }

    //send push notification to receiver(s)
    String notificationBody = message;
    if (messageType == 'post_share') {
      notificationBody = "📜 sent a post!";
    }

    if (isGroup) {
      final groupDoc = await firestore.collection('chats').doc(chatRoomID).get();
      final groupData = groupDoc.data();
      if (groupData != null) {
        final List<String> members = List<String>.from(groupData['members'] ?? []);
        final String groupName = groupData['groupName'] ?? 'Group';
        final List<String> mutedBy = List<String>.from(groupData['mutedBy'] ?? []);
        final String? creatorId = groupData['creatorId'];
        
        // Fetch real sender username from firestore for accuracy
        final senderDoc = await firestore.collection('users').doc(currentUserId).get();
        final senderName = senderDoc.data()?['username'] ?? auth.currentUser?.displayName ?? 'Someone';

        for (String memberId in members) {
          if (memberId != currentUserId && !mutedBy.contains(memberId)) {
            final extra = {
              'isGroup': 'true',
              'groupId': chatRoomID,
              'groupName': groupName,
              'creatorId': creatorId ?? '',
              'senderID': currentUserId,
              'senderUsername': senderName,
            };
            debugPrint('Sending Group Notif to $memberId with data: $extra');
            await sendPushNotification(
              memberId, 
              "$senderName: $notificationBody", 
              title: groupName,
              extraData: extra,
            );
          }
        }
      }
    } else {
      // For private chats, still fetch username for content
      final senderDoc = await firestore.collection('users').doc(currentUserId).get();
      final senderName = senderDoc.data()?['username'] ?? auth.currentUser?.displayName ?? 'Someone';
      
      await sendPushNotification(receiverID, notificationBody, extraData: {
        'senderID': currentUserId,
        'senderUsername': senderName,
      });
    }
  }

  // Share post with multiple users
  Future<void> sharePost(String postId, List<String> receiverIds) async {
    for (String receiverId in receiverIds) {
      await sendMessage(
        receiverId,
        "Shared a post",
        messageType: 'post_share',
        sharedPostId: postId,
      );
    }
  }

  //add or toggle reaction on a message
  Future<void> addReaction(
      String otherUserId, String messageDocId, String emoji, {bool isGroup = false}) async {
    final currentUserId = auth.currentUser!.uid;

    String chatRoomID;
    if (isGroup) {
      chatRoomID = otherUserId;
    } else {
      List<String> ids = [currentUserId, otherUserId];
      ids.sort();
      chatRoomID = ids.join('_');
    }

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
      await docRef.update({'reactions': reactions});
    } else {
      reactions[currentUserId] = emoji;
      await docRef.update({'reactions': reactions});

      // Send notification to the original message sender
      final String originalSenderID = data['senderID'];
      if (originalSenderID != currentUserId) {
        await _sendReactionNotification(originalSenderID, emoji, isGroup: isGroup, groupId: isGroup ? chatRoomID : null);
      }
    }
  }

  // Send notification for reaction
  Future<void> _sendReactionNotification(String receiverID, String emoji, {bool isGroup = false, String? groupId}) async {
    final senderUsername = auth.currentUser?.displayName ?? 'Someone';
    
    String? title;
    Map<String, String>? extra;

    if (isGroup && groupId != null) {
      final groupDoc = await firestore.collection('chats').doc(groupId).get();
      title = groupDoc.data()?['groupName'] ?? 'Group';
      extra = {
        'isGroup': 'true',
        'groupId': groupId,
        'groupName': title!,
        'type': 'chat_message',
      };
    }

    await sendPushNotification(
      receiverID,
      "$senderUsername reacted $emoji to your message",
      title: title, // if null, defaults to senderUsername
      extraData: extra,
    );
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

      final notificationType = extraData?['type'] ?? type ?? 'chat_message';
      final String finalTitle = (title != null && title.isNotEmpty) ? title : senderUsername;

      // Prepare data payload (FCM V1 requires all values to be Strings)
      final Map<String, String> dataPayload = {
        'senderID': auth.currentUser!.uid,
        'senderUsername': senderUsername,
        'type': notificationType,
        'title': finalTitle,
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      };
      
      if (extraData != null) {
        extraData.forEach((key, value) {
          dataPayload[key] = value.toString();
        });
      }

      // Use senderID as tag for chats to stack/replace.
      // For others, use unique tag (timestamp) to keep them separate.
      final String tag = notificationType == 'chat_message'
          ? auth.currentUser!.uid
          : DateTime.now().millisecondsSinceEpoch.toString();

      final body = {
        'message': {
          'token': fcmToken,
          'notification': {
            'title': finalTitle,
            'body': preview,
          },
          'data': dataPayload,
          'android': {
            'notification': {
              'channel_id': 'chat_messages',
              'tag': tag,
            },
          },
        },
      };

      debugPrint('🚀 SENDING NOTIFICATION - Title: "$finalTitle" | Body: "$preview"');
      debugPrint('FCM Payload: ${jsonEncode(body)}');

      //send notification via FCM V1 API
      final response = await http.post(
        Uri.parse(
            'https://fcm.googleapis.com/v1/projects/asiimov-b3792/messages:send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(body),
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
  Stream<QuerySnapshot> getMessages(String userID, String otherUserID, {bool isGroup = false}) {
    String chatRoomID;
    if (isGroup) {
      chatRoomID = otherUserID;
    } else {
      List<String> ids = [userID, otherUserID];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    return firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  //get messages with limit (Added back as helper if needed, but not used by simple getMessages)
  Stream<QuerySnapshot> getMessagesWithLimit(String userID, String otherUserID, int limit, {bool isGroup = false}) {
    String chatRoomID;
    if (isGroup) {
      chatRoomID = otherUserID;
    } else {
      List<String> ids = [userID, otherUserID];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    return firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  //get older messages as a future (pagination)
  Future<QuerySnapshot> getOldMessagesFuture(String userID, String otherUserID, DocumentSnapshot lastDoc, int limit, {bool isGroup = false}) {
    String chatRoomID;
    if (isGroup) {
      chatRoomID = otherUserID;
    } else {
      List<String> ids = [userID, otherUserID];
      ids.sort();
      chatRoomID = ids.join('_');
    }

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

  //mark message as read
  Future<void> markMessageAsRead(String otherUserId, {bool isGroup = false}) async {
    final currentUserId = auth.currentUser!.uid;

    String chatRoomID;
    if (isGroup) {
      chatRoomID = otherUserId;
    } else {
      List<String> ids = [currentUserId, otherUserId];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    if (isGroup) {
      final unreadMessages = await firestore
          .collection('chats')
          .doc(chatRoomID)
          .collection('messages')
          .where('unreadBy', arrayContains: currentUserId)
          .get();

      final batch = firestore.batch();
      for (var doc in unreadMessages.docs) {
        batch.update(doc.reference, {
          'unreadBy': FieldValue.arrayRemove([currentUserId])
        });
      }
      await batch.commit();
    } else {
      final unreadMessages = await firestore
          .collection('chats')
          .doc(chatRoomID)
          .collection('messages')
          .where('receiverID', isEqualTo: currentUserId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = firestore.batch();
      for (var doc in unreadMessages.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    }

    await firestore.collection('chats').doc(chatRoomID).update({
      'lastMessageRead': true,
    }).catchError((_) {});
  }

  //delete old messages with specific conditions
  Future<void> cleanUpOldMessages(String otherUserId, {bool isGroup = false}) async {
    final currentUserId = auth.currentUser?.uid;

    String chatRoomID;
    if (isGroup) {
      chatRoomID = otherUserId;
    } else {
      List<String> ids = [currentUserId ?? '', otherUserId];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    // Get all messages sorted by newest first
    final messagesSnapshot = await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .get();

    final messages = messagesSnapshot.docs;
    final now = DateTime.now();

    // Loop through messages, skipping the first 30 (the most recent ones)
    for (int i = 30; i < messages.length; i++) {
      final doc = messages[i];
      final data = doc.data();
      
      final bool isRead = data['isRead'] ?? false;
      final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

      if (timestamp == null) continue;

      final bool isOlderThan24h = now.difference(timestamp).inHours >= 24;

      // Condition: Read AND Older than 24h AND (already guaranteed) not in top 30
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
