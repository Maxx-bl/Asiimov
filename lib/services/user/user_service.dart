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
}
