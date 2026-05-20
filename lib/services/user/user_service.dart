import 'package:asiimov/services/chat/chat_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  //follow a user
  Future<void> followUser(String targetUserId) async {
    final currentUserId = _auth.currentUser!.uid;
    if (currentUserId == targetUserId) return;

    final batch = _firestore.batch();

    // Add targetUserId to my "following" list
    batch.update(_firestore.collection('users').doc(currentUserId), {
      'following': FieldValue.arrayUnion([targetUserId]),
    });

    // Add my ID to target's "followers" list
    batch.update(_firestore.collection('users').doc(targetUserId), {
      'followers': FieldValue.arrayUnion([currentUserId]),
    });

    await batch.commit();

    // Notification with 1-hour cooldown
    final cooldownDocRef = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('follow_cooldowns')
        .doc(targetUserId);

    final cooldownDoc = await cooldownDocRef.get();

    bool canSendNotif = true;
    if (cooldownDoc.exists) {
      final lastSentData = cooldownDoc.data();
      if (lastSentData != null && lastSentData['timestamp'] != null) {
        final lastSent = (lastSentData['timestamp'] as Timestamp).toDate();
        if (DateTime.now().difference(lastSent).inHours < 1) {
          canSendNotif = false;
        }
      }
    }

    if (canSendNotif) {
      await cooldownDocRef.set({'timestamp': FieldValue.serverTimestamp()});
      
      final senderUsername = _auth.currentUser?.displayName ?? 'Someone';
      await ChatService().sendPushNotification(
        targetUserId, 
        'started following you!', 
        title: '@$senderUsername', 
        type: 'follow' 
      );
    }
  }

  //unfollow a user
  Future<void> unfollowUser(String targetUserId) async {
    final currentUserId = _auth.currentUser!.uid;

    final batch = _firestore.batch();

    batch.update(_firestore.collection('users').doc(currentUserId), {
      'following': FieldValue.arrayRemove([targetUserId]),
    });

    batch.update(_firestore.collection('users').doc(targetUserId), {
      'followers': FieldValue.arrayRemove([currentUserId]),
    });

    await batch.commit();
  }

  //remove a follower from my followers list
  Future<void> removeFollower(String followerId) async {
    final currentUserId = _auth.currentUser!.uid;

    final batch = _firestore.batch();

    // Remove followerId from my "followers" list
    batch.update(_firestore.collection('users').doc(currentUserId), {
      'followers': FieldValue.arrayRemove([followerId]),
    });

    // Remove my ID from follower's "following" list
    batch.update(_firestore.collection('users').doc(followerId), {
      'following': FieldValue.arrayRemove([currentUserId]),
    });

    await batch.commit();
  }

  //stream to check if current user is following target
  Stream<bool> isFollowing(String targetUserId) {
    final currentUserId = _auth.currentUser!.uid;
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .snapshots()
        .map((doc) {
      final following = List<String>.from(doc.data()?['following'] ?? []);
      return following.contains(targetUserId);
    });
  }

  //get user data stream
  Stream<DocumentSnapshot> getUserStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots();
  }

  //get user data future
  Future<DocumentSnapshot> getUserFuture(String userId) {
    return _firestore.collection('users').doc(userId).get();
  }

  //get followers list (user data for each follower)
  Future<List<Map<String, dynamic>>> getFollowers(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    final followerIds = List<String>.from(doc.data()?['followers'] ?? []);

    if (followerIds.isEmpty) return [];

    final List<Map<String, dynamic>> followers = [];
    for (final id in followerIds) {
      final userDoc = await _firestore.collection('users').doc(id).get();
      if (userDoc.exists) {
        followers.add(userDoc.data()!);
      }
    }
    return followers;
  }

  //get following list (user data for each followed user)
  Future<List<Map<String, dynamic>>> getFollowing(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    final followingIds = List<String>.from(doc.data()?['following'] ?? []);

    if (followingIds.isEmpty) return [];

    final List<Map<String, dynamic>> following = [];
    for (final id in followingIds) {
      final userDoc = await _firestore.collection('users').doc(id).get();
      if (userDoc.exists) {
        following.add(userDoc.data()!);
      }
    }
    return following;
  }

  //get user profile by ID
  Future<DocumentSnapshot> getUserProfile(String userId) {
    return _firestore.collection('users').doc(userId).get();
  }

  // --- PRIVACY & FOLLOW REQUESTS ---

  // Toggle account privacy
  Future<void> togglePrivacy(bool isPublic) async {
    final currentUserId = _auth.currentUser!.uid;
    await _firestore.collection('users').doc(currentUserId).set({
      'public_account': isPublic,
    }, SetOptions(merge: true));
    
    // We intentionally do NOT auto-accept pending requests when switching to public (Option B)
  }

  // Toggle Two-Factor Authentication
  Future<void> toggleTwoFactor(bool enabled) async {
    final currentUserId = _auth.currentUser!.uid;
    await _firestore.collection('users').doc(currentUserId).set({
      'two_factor_enabled': enabled,
    }, SetOptions(merge: true));
  }

  // Request to follow a private account
  Future<void> requestFollow(String targetUserId) async {
    final currentUserId = _auth.currentUser!.uid;
    if (currentUserId == targetUserId) return;

    final batch = _firestore.batch();
    batch.update(_firestore.collection('users').doc(targetUserId), {
      'follow_requests': FieldValue.arrayUnion([currentUserId]),
    });
    await batch.commit();

    // Notification with 1-hour cooldown to prevent spam
    final cooldownDocRef = _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('follow_cooldowns')
        .doc(targetUserId);

    final cooldownDoc = await cooldownDocRef.get();

    bool canSendNotif = true;
    if (cooldownDoc.exists) {
      final lastSentData = cooldownDoc.data();
      if (lastSentData != null && lastSentData['timestamp'] != null) {
        final lastSent = (lastSentData['timestamp'] as Timestamp).toDate();
        if (DateTime.now().difference(lastSent).inHours < 1) {
          canSendNotif = false;
        }
      }
    }

    if (canSendNotif) {
      await cooldownDocRef.set({'timestamp': FieldValue.serverTimestamp()});
      
      final senderUsername = _auth.currentUser?.displayName ?? 'Someone';
      await ChatService().sendPushNotification(
        targetUserId,
        'wants to follow you!',
        title: '@$senderUsername',
        type: 'follow_request',
      );
    }
  }

  // Cancel a follow request sent to a private account
  Future<void> cancelFollowRequest(String targetUserId) async {
    final currentUserId = _auth.currentUser!.uid;
    await _firestore.collection('users').doc(targetUserId).update({
      'follow_requests': FieldValue.arrayRemove([currentUserId]),
    });
  }

  // Accept a follow request
  Future<void> acceptFollowRequest(String requesterId) async {
    final currentUserId = _auth.currentUser!.uid;
    final batch = _firestore.batch();

    // Remove from follow_requests
    batch.update(_firestore.collection('users').doc(currentUserId), {
      'follow_requests': FieldValue.arrayRemove([requesterId]),
    });

    // Add requester to my followers
    batch.update(_firestore.collection('users').doc(currentUserId), {
      'followers': FieldValue.arrayUnion([requesterId]),
    });

    // Add me to requester's following
    batch.update(_firestore.collection('users').doc(requesterId), {
      'following': FieldValue.arrayUnion([currentUserId]),
    });

    await batch.commit();
    
    // Optional: Send notification back to requester that request was accepted
    final myUsername = _auth.currentUser?.displayName ?? 'Someone';
    await ChatService().sendPushNotification(
      requesterId,
      'accepted your follow request!',
      title: '@$myUsername',
      type: 'follow_accept',
    );
  }

  // Decline a follow request
  Future<void> declineFollowRequest(String requesterId) async {
    final currentUserId = _auth.currentUser!.uid;
    await _firestore.collection('users').doc(currentUserId).update({
      'follow_requests': FieldValue.arrayRemove([requesterId]),
    });
  }

  // Stream to check if current user has requested to follow target
  Stream<bool> hasRequestedFollow(String targetUserId) {
    final currentUserId = _auth.currentUser!.uid;
    return _firestore
        .collection('users')
        .doc(targetUserId)
        .snapshots()
        .map((doc) {
      final requests = List<String>.from(doc.data()?['follow_requests'] ?? []);
      return requests.contains(currentUserId);
    });
  }

  // Future to check if current user has requested to follow target
  Future<bool> hasRequestedFollowFuture(String targetUserId) async {
    final currentUserId = _auth.currentUser!.uid;
    final doc = await _firestore.collection('users').doc(targetUserId).get();
    final requests = List<String>.from(doc.data()?['follow_requests'] ?? []);
    return requests.contains(currentUserId);
  }

  // Stream to get follow requests for a user
  Stream<List<String>> getFollowRequestsStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) {
      return List<String>.from(doc.data()?['follow_requests'] ?? []);
    });
  }

  // Future to get follow requests for a user
  Future<List<String>> getFollowRequestsFuture(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    return List<String>.from(doc.data()?['follow_requests'] ?? []);
  }

  // Toggle close friends functionality
  Future<void> toggleCloseFriendsFeature(bool enabled) async {
    final currentUserId = _auth.currentUser!.uid;
    await _firestore.collection('users').doc(currentUserId).set({
      'closeFriendsEnabled': enabled,
    }, SetOptions(merge: true));
  }

  // Update a user in current user's close friends list
  Future<void> updateCloseFriend(String targetUid, bool isAdded) async {
    final currentUserId = _auth.currentUser!.uid;
    await _firestore.collection('users').doc(currentUserId).update({
      'closeFriends': isAdded
          ? FieldValue.arrayUnion([targetUid])
          : FieldValue.arrayRemove([targetUid]),
    });
  }
}
