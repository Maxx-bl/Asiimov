import 'dart:async';

import 'package:asiimov/models/conversation.dart';
import 'package:asiimov/models/message.dart';
import 'package:asiimov/services/encryption/conversation_key_service.dart';
import 'package:asiimov/services/encryption/encryption_service.dart';
import 'package:asiimov/services/file/file_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rxdart/rxdart.dart';
import 'package:easy_localization/easy_localization.dart';

class ChatService extends ChangeNotifier {
  //get instance of firebase services
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;
  final EncryptionService encryption =
      EncryptionService(dotenv.env['ENCRYPTION_KEY'] ?? '');

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

  // In-memory cache for user profiles (avoids re-fetching on every stream emission)
  final Map<String, Map<String, dynamic>> _userProfileCache = {};

  // OPTIMIZED: Conversation list stream — fetches only needed users, not ALL users
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

    // Stream 3: Blocked users (lightweight — only my sub-collection)
    final blockedStream = firestore
        .collection('users')
        .doc(currentUserId)
        .collection('blockedUsers')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.id).toList());

    // Combine 3 streams instead of 4 — NO global users stream
    return CombineLatestStream.combine3(
      chatsStream,
      unreadStream,
      blockedStream,
      (chatDocs, unreadMap, blockedIds) => _ConversationStreamData(chatDocs, unreadMap, blockedIds),
    ).asyncMap((data) async {
      final chatDocs = data.chatDocs;
      final unreadMap = data.unreadMap;
      final blockedIds = data.blockedIds;

      // 1. Extract only the user IDs we need from private chats
      final Set<String> neededUserIds = {};
      for (final chatDoc in chatDocs) {
        final chatData = chatDoc.data();
        if (chatData['type'] != 'group') {
          final ids = chatDoc.id.split('_');
          if (ids.length >= 2) {
            final otherUserId = ids.firstWhere((id) => id != currentUserId, orElse: () => ids.first);
            if (otherUserId.isNotEmpty && !blockedIds.contains(otherUserId)) {
              neededUserIds.add(otherUserId);
            }
          }
        }
      }

      // 2. Fetch only MISSING user profiles (cache-first)
      final uncachedIds = neededUserIds.where((id) => !_userProfileCache.containsKey(id)).toList();
      if (uncachedIds.isNotEmpty) {
        // Firestore 'whereIn' limit is 30
        for (int i = 0; i < uncachedIds.length; i += 30) {
          final batch = uncachedIds.sublist(i, (i + 30).clamp(0, uncachedIds.length));
          final usersSnapshot = await firestore
              .collection('users')
              .where(FieldPath.documentId, whereIn: batch)
              .get();
          for (final doc in usersSnapshot.docs) {
            _userProfileCache[doc.id] = doc.data();
          }
        }
      }

      // 3. Build conversation list
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
          if (ids.length < 2) continue;
          otherUserId = ids.firstWhere((id) => id != currentUserId, orElse: () => ids.first);
        }

        if (otherUserId.isEmpty) continue;
        if (!isGroup && blockedIds.contains(otherUserId)) continue;

        final otherUserData = isGroup ? <String, dynamic>{} : _userProfileCache[otherUserId];
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
          groupIconUrl: chatData['groupIconUrl'],
          lastMessage: chatData['lastMessage'] != null ? {
            'message': chatData['lastMessage'],
            'senderID': chatData['lastSenderID'],
            'senderUsername': chatData['lastSenderUsername'],
            'timestamp': chatData['lastTimestamp'],
            'isRead': chatData['lastMessageRead'] ?? false,
            'isSystemMessage': chatData['lastIsSystem'] ?? false,
          } : null,
          lastReaction: chatData['lastReactionEmoji'] != null ? {
            'emoji': chatData['lastReactionEmoji'],
            'senderID': chatData['lastReactionSenderID'],
            'senderUsername': chatData['lastReactionSenderUsername'],
            'timestamp': chatData['lastReactionTimestamp'],
          } : null,
        ));
      }

      conversations.sort((a, b) => b.lastActive.compareTo(a.lastActive));

      // Pre-load conversation keys so the home page can decrypt message previews
      // without needing to open each conversation first.
      await Future.wait(conversations.map((conv) async {
        final chatRoomId = conv.isGroup
            ? conv.id
            : ([currentUserId, conv.id]..sort()).join('_');
        if (ConversationKeyService.getCachedKey(chatRoomId) != null) return;
        try {
          final participantIds = conv.isGroup
              ? (conv.members ?? [currentUserId])
              : [currentUserId, conv.id];
          await ConversationKeyService.getOrCreateConversationKey(
              chatRoomId, participantIds);
        } catch (_) {}
      }));

      return conversations;
    });
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

  // NEW: Log group picture update/delete
  Future<void> logGroupPictureUpdate(String groupId, bool isDeleted) async {
    final currentUsername = auth.currentUser?.displayName ?? 'Someone';
    final action = isDeleted ? "removed the group photo" : "updated the group photo";
    await sendSystemMessage(groupId, "$currentUsername $action");
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

    // Distribute conversation E2EE key to newly added members
    if (added.isNotEmpty) {
      try {
        // Load key from cache or Firestore before distributing
        final convKey = ConversationKeyService.getCachedKey(groupId) ??
            await ConversationKeyService.getOrCreateConversationKey(
              groupId, [currentUserId, ...newMemberIds]);
        for (final uid in added) {
          await ConversationKeyService.addParticipant(groupId, uid, convKey);
        }
      } catch (_) {}
    }

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
    try {
      final currentUserId = auth.currentUser!.uid;
      final currentUsername = auth.currentUser?.displayName ?? 'Someone';
      
      final groupDoc = await firestore.collection('chats').doc(groupId).get();
      final data = groupDoc.data();
      if (data == null) return;

      List<String> members = List<String>.from(data['members'] ?? []);
      final String creatorId = data['creatorId'] ?? '';
      Map<String, dynamic> memberDetails = Map<String, dynamic>.from(data['memberDetails'] ?? {});

      // 1. Remove me from members and details
      members.remove(currentUserId);
      memberDetails.remove(currentUserId);

      if (members.isEmpty) {
        // Last person left, delete the chat
        await firestore.collection('chats').doc(groupId).delete();
        return;
      }

      // 1. Prepare updates with atomic operations
      final Map<String, dynamic> updates = {
        'members': FieldValue.arrayRemove([currentUserId]),
        'memberDetails.$currentUserId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      String? nextAdmin;
      String adminUsername = 'Someone';

      // 2. If I was the creator, find a successor
      if (currentUserId == creatorId) {
        Timestamp? oldestTimestamp;

        memberDetails.forEach((uid, timestamp) {
          if (uid != currentUserId && timestamp != null) {
            Timestamp? t;
            if (timestamp is Timestamp) {
              t = timestamp;
            } else if (timestamp is Map && timestamp['_seconds'] != null) {
              t = Timestamp(timestamp['_seconds'], timestamp['_nanoseconds'] ?? 0);
            }

            if (t != null) {
              if (oldestTimestamp == null || t.compareTo(oldestTimestamp!) < 0) {
                oldestTimestamp = t;
                nextAdmin = uid;
              }
            }
          }
        });

        // Fallback: if no valid timestamp found, pick any other member
        if (nextAdmin == null) {
          final otherMembers = members.where((m) => m != currentUserId).toList();
          if (otherMembers.isNotEmpty) {
            nextAdmin = otherMembers.first;
          }
        }
        
        if (nextAdmin != null) {
          updates['creatorId'] = nextAdmin;
          
          // Fetch new admin username
          try {
            final adminDoc = await firestore.collection('users').doc(nextAdmin).get();
            adminUsername = adminDoc.data()?['username'] ?? 'Someone';
          } catch (e) {
            debugPrint("Error fetching new admin name: $e");
          }
        }
      }

      // 3. APPLY UPDATES FIRST (CRITICAL)
      await firestore.collection('chats').doc(groupId).update(updates);

      // 4. Then send system message (if we still have access or via server-side if needed, 
      // but here we try while still having the local token valid for a few ms)
      try {
        if (nextAdmin != null) {
          await sendSystemMessage(groupId, "$currentUsername left the group. @$adminUsername is the new admin.");
        } else {
          await sendSystemMessage(groupId, "$currentUsername left the group.");
        }
      } catch (e) {
        debugPrint("Silent error sending system message after leaving: $e");
      }
    } catch (e) {
      debugPrint("❌ Error leaving group: $e");
      // Rethrow to let the UI know if needed, but the important part is we tried to clean up
      rethrow;
    }
  }

  //send message
  Future<void> sendMessage(String receiverID, String message,
      {bool isGroup = false,
      String? replyToMessageId,
      String? replyToMessage,
      String? replyToSenderID,
      String? replyToSenderUsername,
      String messageType = 'text',
      String? sharedPostId,
      List<dynamic>? attachments,
      Map<String, dynamic>? instantAttachment,
      Map<String, String>? mentions}) async {
    //get current user info
    final String currentUserId = auth.currentUser!.uid;
    final String currentUserEmail = auth.currentUser!.email!;
    final String senderName = auth.currentUser?.displayName ?? 'Someone';
    final Timestamp timestamp = Timestamp.now();

    // For groups, fetch the doc ONCE and reuse for unread + notifications
    Map<String, dynamic>? groupData;
    List<String> unreadBy = [];
    List<String> participantIds;
    if (isGroup) {
      final groupDoc = await firestore.collection('chats').doc(receiverID).get();
      groupData = groupDoc.data();
      final List<String> members = List<String>.from(groupData?['members'] ?? []);
      unreadBy = members.where((id) => id != currentUserId).toList();
      participantIds = members;
    } else {
      participantIds = [currentUserId, receiverID];
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

    // Encrypt with per-conversation key (E2EE), fallback to global key if user has no E2EE keys yet
    String encryptedMessage;
    String? encryptedReplyToMessage;
    try {
      final convKey = await ConversationKeyService.getOrCreateConversationKey(chatRoomID, participantIds);
      encryptedMessage = EncryptionService.encryptWithKey(message, convKey);
      if (replyToMessage != null) {
        encryptedReplyToMessage = EncryptionService.encryptWithKey(replyToMessage, convKey);
      }
    } catch (_) {
      encryptedMessage = encryption.encrypt(message);
      if (replyToMessage != null) {
        encryptedReplyToMessage = encryption.encrypt(replyToMessage);
      }
    }

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
      replyToMessage: encryptedReplyToMessage,
      replyToSenderID: replyToSenderID,
      replyToSenderUsername: replyToSenderUsername,
      attachments: attachments,
      instantAttachment: instantAttachment,
      mentions: mentions,
    );

    // Format notification body (stored for Cloud Function trigger)
    String notifBody = message;
    if (messageType == 'post_share') {
      notifBody = 'notif_sent_post'.tr();
    } else if (messageType == 'instant_attachment' && instantAttachment != null) {
      final type = instantAttachment['type'];
      if (type == 'audio') {
        notifBody = 'notif_sent_voice'.tr();
      } else if (type == 'video') {
        notifBody = "📸 sent a video";
      } else {
        notifBody = "📸 sent a photo";
      }
    } else if (attachments != null && attachments.isNotEmpty) {
      if (message.isEmpty) {
        if (attachments.length == 1) {
          final type = attachments[0]['type'];
          if (type == 'image') {
            notifBody = "📷 sent a photo";
          } else if (type == 'video') {
            notifBody = "🎥 sent a video";
          } else if (type == 'audio') {
            notifBody = "🎵 sent an audio file";
          } else {
            notifBody = 'notif_sent_attachment'.tr();
          }
        } else {
          notifBody = "📁 sent ${attachments.length} attachments";
        }
      } else {
        if (attachments.length == 1) {
          final type = attachments[0]['type'];
          if (type == 'image') {
            notifBody = "📷 Photo: $message";
          } else if (type == 'video') {
            notifBody = "🎥 Video: $message";
          } else if (type == 'audio') {
            notifBody = "🎵 Audio: $message";
          } else {
            notifBody = "📁 Attachment: $message";
          }
        } else {
          notifBody = "📁 ${attachments.length} attachments: $message";
        }
      }
    }

    //add to db
    final messageMap = newMessage.toMap();
    messageMap['senderUsername'] = senderName;
    messageMap['notifBody'] = notifBody;
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
      'lastSenderUsername': senderName,
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
  }

  // Share post with multiple users
  Future<void> sharePost(String postId, List<String> receiverIds) async {
    for (String receiverId in receiverIds) {
      await sendMessage(
        receiverId,
        'shared_a_post'.tr(),
        messageType: 'post_share',
        sharedPostId: postId,
      );
    }
  }

  //add or toggle reaction on a message
  Future<void> addReaction(
      String otherUserId, String messageDocId, String emoji, {bool isGroup = false}) async {
    final currentUserId = auth.currentUser!.uid;
    final currentUsername = auth.currentUser?.displayName ?? 'Someone';

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
      // Clear lastReaction only if it was set by the current user
      final chatDoc = await firestore.collection('chats').doc(chatRoomID).get();
      if (chatDoc.data()?['lastReactionSenderID'] == currentUserId) {
        await firestore.collection('chats').doc(chatRoomID).update({
          'lastReactionEmoji': FieldValue.delete(),
          'lastReactionSenderID': FieldValue.delete(),
          'lastReactionSenderUsername': FieldValue.delete(),
          'lastReactionTimestamp': FieldValue.delete(),
        });
      }
    } else {
      reactions[currentUserId] = emoji;
      await docRef.update({'reactions': reactions});

      // Update lastReaction in chat doc
      await firestore.collection('chats').doc(chatRoomID).set({
        'lastReactionEmoji': emoji,
        'lastReactionSenderID': currentUserId,
        'lastReactionSenderUsername': currentUsername,
        'lastReactionTimestamp': Timestamp.now(),
      }, SetOptions(merge: true));

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
    final senderID = auth.currentUser?.uid ?? '';

    String title;
    Map<String, String> extra;
    String androidTag;

    if (isGroup && groupId != null) {
      final groupDoc = await firestore.collection('chats').doc(groupId).get();
      title = groupDoc.data()?['groupName'] ?? 'Group';
      extra = {
        'isGroup': 'true',
        'groupId': groupId,
        'groupName': title,
        'senderUsername': senderUsername,
        'type': 'chat_message',
      };
      androidTag = groupId;
    } else {
      title = senderUsername;
      extra = {
        'senderUsername': senderUsername,
        'type': 'chat_message',
      };
      androidTag = senderID;
    }

    await sendPushNotification(
      receiverID,
      "$senderUsername reacted $emoji to your message",
      title: title,
      type: 'chat_message',
      extraData: extra,
      androidTag: androidTag,
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

  // ─── Typing indicator ───────────────────────────────────────────────────────

  Future<void> setTypingStatus(String chatRoomId, bool isTyping) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    final ref = firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('typing')
        .doc(uid);
    if (isTyping) {
      await ref.set({
        'at': Timestamp.now(),
        'name': auth.currentUser?.displayName ?? 'Someone',
      });
    } else {
      await ref.delete().catchError((_) {});
    }
  }

  /// Returns the display names of other users currently typing.
  Stream<List<String>> getTypingUsernamesStream(String chatRoomId) {
    final uid = auth.currentUser?.uid ?? '';
    return firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('typing')
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      return snapshot.docs
          .where((doc) => doc.id != uid)
          .where((doc) {
            final at = (doc.data()['at'] as Timestamp?)?.toDate();
            if (at == null) return false;
            // Discard stale entries (crash / network failure safety net)
            return now.difference(at).inSeconds < 10;
          })
          .map((doc) => (doc.data()['name'] as String?) ?? 'Someone')
          .toList();
    });
  }

  // ────────────────────────────────────────────────────────────────────────────

  Future<void> sendPushNotification(String receiverID, String messageText,
      {String? title, String? type, Map<String, dynamic>? extraData, String? androidTag}) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('sendNotification');
      await callable.call({
        'receiverID': receiverID,
        'message': messageText,
        if (title != null) 'title': title,
        'type': type ?? 'notification',
        if (extraData != null) 'extraData': extraData,
        if (androidTag != null) 'androidTag': androidTag,
      });
    } catch (e) {
      debugPrint('Error calling sendNotification function: $e');
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
        .snapshots(includeMetadataChanges: true);
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

    // Only update lastMessageRead when the last message is from the OTHER person.
    // If the last message is ours, don't touch the flag — only the recipient should.
    try {
      final chatDoc = await firestore.collection('chats').doc(chatRoomID).get();
      final chatData = chatDoc.data();
      if (chatData != null && chatData['lastSenderID'] != currentUserId) {
        await firestore.collection('chats').doc(chatRoomID).update({
          'lastMessageRead': true,
        });
      }
    } catch (_) {}
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

    // First, get the 30th message to use as cursor (skip the 30 most recent)
    final recentSnapshot = await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(30)
        .get();

    // If there are fewer than 30 messages, nothing to clean
    if (recentSnapshot.docs.length < 30) return;

    // Get only messages OLDER than the 30th most recent
    final lastProtectedDoc = recentSnapshot.docs.last;
    final oldMessagesSnapshot = await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .startAfterDocument(lastProtectedDoc)
        .get();

    if (oldMessagesSnapshot.docs.isEmpty) return;

    final now = DateTime.now();
    final batch = firestore.batch();
    final fileService = FileService();
    int deleteCount = 0;

    for (final doc in oldMessagesSnapshot.docs) {
      final data = doc.data();
      
      // Check read status based on chat type
      bool isEffectivelyRead = false;
      if (isGroup) {
        // In groups, messages older than 24h are deleted even if not read by everyone
        isEffectivelyRead = true;
      } else {
        isEffectivelyRead = data['isRead'] == true;
      }

      final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
      if (timestamp == null) continue;

      final bool isOlderThan24h = now.difference(timestamp).inHours >= 24;
      final bool isPinned = data['isPinned'] == true;

      // Condition: Read AND Older than 24h AND not pinned AND (already guaranteed) not in top 30
      if (isEffectivelyRead && isOlderThan24h && !isPinned) {
        // 1. Delete associated R2 attachments if any
        final attachments = data['attachments'] as List<dynamic>?;
        if (attachments != null && attachments.isNotEmpty) {
          for (var attachment in attachments) {
            final objectKey = attachment['objectKey'] as String?;
            if (objectKey != null) {
              await fileService.deleteAttachment(objectKey);
            }
          }
        }

        final instantAttachment = data['instantAttachment'] as Map<String, dynamic>?;
        if (instantAttachment != null) {
          final objectKey = instantAttachment['objectKey'] as String?;
          if (objectKey != null) {
            await fileService.deleteAttachment(objectKey);
          }
        }

        // 2. Delete message document
        batch.delete(doc.reference);
        deleteCount++;

        // Firestore batches are limited to 500 operations
        if (deleteCount >= 500) break;
      }
    }

    if (deleteCount > 0) {
      await batch.commit();
    }
  }

  //report user
  Future<void> reportUser(
      String messageId,
      String userId,
      String content,
      String chatRoomId,
      String senderUsername,
      String reporterUsername, {
      required String reason,
      String messageType = 'text',
      String? sharedPostId,
      List<String>? attachmentTypes,
  }) async {
    final currentUser = auth.currentUser!;
    final reasonEntry = {
      'userId': currentUser.uid,
      'username': reporterUsername,
      'reason': reason.trim(),
    };

    // Check for an existing pending report for this message
    final existing = await firestore.collection('reports')
        .where('messageId', isEqualTo: messageId)
        .where('chatRoomId', isEqualTo: chatRoomId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final reportDoc = existing.docs.first;
      await reportDoc.reference.update({
        'reportCount': FieldValue.increment(1),
        'reportedByIds': FieldValue.arrayUnion([currentUser.uid]),
        'reporterReasons': FieldValue.arrayUnion([reasonEntry]),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } else {
      final report = {
        'reportedById': currentUser.uid,
        'reportedByIds': [currentUser.uid],
        'reportedByUsername': reporterUsername,
        'reportReason': reasonEntry['reason'],
        'reporterReasons': [reasonEntry],
        'messageId': messageId,
        'messageOwnerId': userId,
        'messageContent': content,
        'chatRoomId': chatRoomId,
        'messageAuthorUsername': senderUsername,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'type': 'message',
        'messageType': messageType,
        'sharedPostId': sharedPostId,
        'attachmentTypes': attachmentTypes ?? [],
        'reportCount': 1,
      };
      await firestore.collection('reports').add(report);
    }

    // Increment reportsCount for the sender
    await firestore.collection('users').doc(userId).update({
      'reportsCount': FieldValue.increment(1),
    });
  }

  // delete message by room id (called by Admin Dashboard)
  Future<void> deleteMessageByRoomId(String chatRoomId, String messageId) async {
    final messageRef = firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .doc(messageId);

    // Fetch message to check for attachments
    final doc = await messageRef.get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final fileService = FileService();

      final attachments = data['attachments'] as List<dynamic>?;
      if (attachments != null && attachments.isNotEmpty) {
        for (var attachment in attachments) {
          final objectKey = attachment['objectKey'] as String?;
          if (objectKey != null) {
            await fileService.deleteAttachment(objectKey);
          }
        }
      }

      final instantAttachment = data['instantAttachment'] as Map<String, dynamic>?;
      if (instantAttachment != null) {
        final objectKey = instantAttachment['objectKey'] as String?;
        if (objectKey != null) {
          await fileService.deleteAttachment(objectKey);
        }
      }
    }

    await messageRef.delete();
    await _updateLastMessageAfterDeletion(chatRoomId);
  }

  // Helper to update the last message in a chat room after a deletion
  Future<void> _updateLastMessageAfterDeletion(String chatRoomID) async {
    try {
      final messagesRef = firestore
          .collection('chats')
          .doc(chatRoomID)
          .collection('messages');
      
      final latestMessagesSnapshot = await messagesRef
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (latestMessagesSnapshot.docs.isNotEmpty) {
        final latestMessage = latestMessagesSnapshot.docs.first.data();
        await firestore.collection('chats').doc(chatRoomID).update({
          'lastMessage': latestMessage['message'] ?? '',
          'lastSenderID': latestMessage['senderID'] ?? '',
          'lastSenderUsername': latestMessage['senderUsername'] ?? '',
          'lastTimestamp': latestMessage['timestamp'],
          'lastMessageRead': latestMessage['isRead'] ?? false,
          'lastIsSystem': latestMessage['isSystemMessage'] ?? false,
        });
      } else {
        await firestore.collection('chats').doc(chatRoomID).update({
          'lastMessage': '',
          'lastSenderID': '',
          'lastSenderUsername': '',
          'lastTimestamp': FieldValue.serverTimestamp(),
          'lastMessageRead': true,
          'lastIsSystem': false,
        });
      }
    } catch (e) {
      debugPrint("Error updating last message after deletion: $e");
    }
  }

  //block user
  Future<void> blockUser(String userId) async {
    final currentUser = auth.currentUser;
    final currentUserId = currentUser!.uid;

    final batch = firestore.batch();

    // 1. Add to blockedUsers collection of current user
    batch.set(
      firestore.collection('users').doc(currentUserId).collection('blockedUsers').doc(userId),
      <String, dynamic>{}
    );

    // 2. Unfollow each other, clear pending requests, and remove from close friends on both profiles
    batch.update(firestore.collection('users').doc(currentUserId), {
      'following': FieldValue.arrayRemove([userId]),
      'followers': FieldValue.arrayRemove([userId]),
      'follow_requests': FieldValue.arrayRemove([userId]),
      'closeFriends': FieldValue.arrayRemove([userId]),
    });

    batch.update(firestore.collection('users').doc(userId), {
      'following': FieldValue.arrayRemove([currentUserId]),
      'followers': FieldValue.arrayRemove([currentUserId]),
      'follow_requests': FieldValue.arrayRemove([currentUserId]),
      'closeFriends': FieldValue.arrayRemove([currentUserId]),
    });

    await batch.commit();
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
  Future<void> deleteMessage(String otherUserId, String messageId, {bool isGroup = false}) async {
    final currentUserId = auth.currentUser!.uid;

    String chatRoomID;
    if (isGroup) {
      chatRoomID = otherUserId;
    } else {
      List<String> ids = [currentUserId, otherUserId];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    final messageRef = firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .doc(messageId);

    // Fetch message to check for attachments
    final doc = await messageRef.get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final fileService = FileService();

      final attachments = data['attachments'] as List<dynamic>?;
      if (attachments != null && attachments.isNotEmpty) {
        for (var attachment in attachments) {
          final objectKey = attachment['objectKey'] as String?;
          if (objectKey != null) {
            await fileService.deleteAttachment(objectKey);
          }
        }
      }

      final instantAttachment = data['instantAttachment'] as Map<String, dynamic>?;
      if (instantAttachment != null) {
        final objectKey = instantAttachment['objectKey'] as String?;
        if (objectKey != null) {
          await fileService.deleteAttachment(objectKey);
        }
      }
    }

    await messageRef.delete();
    await _updateLastMessageAfterDeletion(chatRoomID);
  }

  //edit message
  Future<void> editMessage(String otherUserId, String messageId, String newMessage, {bool isGroup = false}) async {
    final currentUserId = auth.currentUser!.uid;

    String chatRoomID;
    if (isGroup) {
      chatRoomID = otherUserId;
    } else {
      List<String> ids = [currentUserId, otherUserId];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    // Encrypt with per-conversation key, fallback to global key
    String encryptedMessage;
    try {
      final convKey = ConversationKeyService.getCachedKey(chatRoomID) ??
          await ConversationKeyService.getOrCreateConversationKey(
              chatRoomID, [currentUserId, otherUserId]);
      encryptedMessage = EncryptionService.encryptWithKey(newMessage, convKey);
    } catch (_) {
      encryptedMessage = encryption.encrypt(newMessage);
    }

    await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .doc(messageId)
        .update({
          'message': encryptedMessage,
          'isEdited': true,
        });
  }

  //toggle pin message
  Future<void> togglePinMessage(String otherUserId, String messageId, bool currentPinState, {bool isGroup = false}) async {
    final currentUserId = auth.currentUser!.uid;
    
    String chatRoomID;
    if (isGroup) {
      chatRoomID = otherUserId;
    } else {
      List<String> ids = [currentUserId, otherUserId];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    await firestore
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .doc(messageId)
        .update({
          'isPinned': !currentPinState,
        });
  }
}

// Helper class to bundle stream data for asyncMap
class _ConversationStreamData {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> chatDocs;
  final Map<String, int> unreadMap;
  final List<String> blockedIds;

  _ConversationStreamData(this.chatDocs, this.unreadMap, this.blockedIds);
}
