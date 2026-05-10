import 'package:asiimov/services/chat/chat_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PostService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  //create a new post
  Future<void> createPost(String content) async {
    final user = _auth.currentUser!;

    // Check for cooldown (120 seconds)
    final lastPost = await _firestore
        .collection('posts')
        .where('authorID', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (lastPost.docs.isNotEmpty) {
      final timestamp = lastPost.docs.first['timestamp'] as Timestamp?;
      if (timestamp != null) {
        final diff = DateTime.now().difference(timestamp.toDate()).inSeconds;
        if (diff < 120) {
          throw Exception(
              'Please wait ${120 - diff} more seconds before posting again.');
        }
      }
    }

    await _firestore.collection('posts').add({
      'authorID': user.uid,
      'authorUsername': user.displayName ?? 'Anonymous',
      'content': content,
      'timestamp': FieldValue.serverTimestamp(),
      'upvotes': [],
      'downvotes': [],
      'commentCount': 0,
      'shareCount': 0,
      'sharedBy': [],
    });
  }

  // Increment share count and record who shared it
  Future<void> incrementShareCount(String postId, String userId) async {
    await _firestore.collection('posts').doc(postId).update({
      'shareCount': FieldValue.increment(1),
      'sharedBy': FieldValue.arrayUnion([userId]),
    });
  }

  //get posts future (for manual refresh)
  Future<QuerySnapshot> getPostsFuture(int limit) {
    return _firestore
        .collection('posts')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
  }

  //get a single post stream (keep live for vote updates on specific post)
  Stream<DocumentSnapshot> getPostStream(String postId) {
    return _firestore.collection('posts').doc(postId).snapshots();
  }

  //get comments future for a post
  Future<QuerySnapshot> getCommentsFuture(String postId, int limit) {
    return _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
  }

  //get posts stream for a specific user
  Stream<QuerySnapshot> getUserPostsStream(String userId) {
    return _firestore
        .collection('posts')
        .where('authorID', isEqualTo: userId)
        .snapshots();
  }

  //toggle upvote on a post
  Future<void> upvotePost(String postId) async {
    final userId = _auth.currentUser!.uid;
    final docRef = _firestore.collection('posts').doc(postId);

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(docRef);
      if (!doc.exists) return;

      final upvotes = List<String>.from(doc['upvotes'] ?? []);
      final downvotes = List<String>.from(doc['downvotes'] ?? []);

      if (upvotes.contains(userId)) {
        // Already upvoted → remove upvote
        upvotes.remove(userId);
      } else {
        // Add upvote and remove downvote if present
        upvotes.add(userId);
        downvotes.remove(userId);
      }

      transaction.update(docRef, {
        'upvotes': upvotes,
        'downvotes': downvotes,
      });
    });
  }

  //toggle downvote on a post
  Future<void> downvotePost(String postId) async {
    final userId = _auth.currentUser!.uid;
    final docRef = _firestore.collection('posts').doc(postId);

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(docRef);
      if (!doc.exists) return;

      final upvotes = List<String>.from(doc['upvotes'] ?? []);
      final downvotes = List<String>.from(doc['downvotes'] ?? []);

      if (downvotes.contains(userId)) {
        // Already downvoted → remove downvote
        downvotes.remove(userId);
      } else {
        // Add downvote and remove upvote if present
        downvotes.add(userId);
        upvotes.remove(userId);
      }

      transaction.update(docRef, {
        'upvotes': upvotes,
        'downvotes': downvotes,
      });
    });
  }

  //delete a post (only if author)
  Future<void> deletePost(String postId) async {
    final userId = _auth.currentUser!.uid;
    final doc = await _firestore.collection('posts').doc(postId).get();
    if (doc.exists && doc['authorID'] == userId) {
      // Delete all comments first
      final comments = await _firestore
          .collection('posts')
          .doc(postId)
          .collection('comments')
          .get();
      for (final comment in comments.docs) {
        await comment.reference.delete();
      }
      await _firestore.collection('posts').doc(postId).delete();
    }
  }

  //add a comment to a post
  Future<void> addComment(String postId, String content) async {
    final user = _auth.currentUser!;
    final postRef = _firestore.collection('posts').doc(postId);

    await postRef.collection('comments').add({
      'authorID': user.uid,
      'authorUsername': user.displayName ?? 'Anonymous',
      'content': content,
      'timestamp': FieldValue.serverTimestamp(),
      'upvotes': [],
      'downvotes': [],
    });

    // Increment comment count
    await postRef.update({
      'commentCount': FieldValue.increment(1),
    });

    // Fetch post to send notification
    final postDoc = await postRef.get();
    if (postDoc.exists) {
      final postOwnerID = postDoc.data()?['authorID'] as String?;
      if (postOwnerID != null && postOwnerID != user.uid) {
        final senderUsername = user.displayName ?? 'Someone';
        await ChatService().sendPushNotification(
          postOwnerID,
          content,
          title: '$senderUsername commented on your post',
          type: 'comment',
          extraData: {'postId': postId},
        );
      }
    }
  }

  //toggle upvote on a comment
  Future<void> upvoteComment(String postId, String commentId) async {
    final userId = _auth.currentUser!.uid;
    final docRef = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(docRef);
      if (!doc.exists) return;

      final upvotes = List<String>.from(doc['upvotes'] ?? []);
      final downvotes = List<String>.from(doc['downvotes'] ?? []);

      if (upvotes.contains(userId)) {
        upvotes.remove(userId);
      } else {
        upvotes.add(userId);
        downvotes.remove(userId);
      }

      transaction.update(docRef, {
        'upvotes': upvotes,
        'downvotes': downvotes,
      });
    });
  }

  //toggle downvote on a comment
  Future<void> downvoteComment(String postId, String commentId) async {
    final userId = _auth.currentUser!.uid;
    final docRef = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(docRef);
      if (!doc.exists) return;

      final upvotes = List<String>.from(doc['upvotes'] ?? []);
      final downvotes = List<String>.from(doc['downvotes'] ?? []);

      if (downvotes.contains(userId)) {
        downvotes.remove(userId);
      } else {
        downvotes.add(userId);
        upvotes.remove(userId);
      }

      transaction.update(docRef, {
        'upvotes': upvotes,
        'downvotes': downvotes,
      });
    });
  }

  //delete a comment (only if author)
  Future<void> deleteComment(String postId, String commentId) async {
    final userId = _auth.currentUser!.uid;
    final commentRef = _firestore
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .doc(commentId);

    final doc = await commentRef.get();
    if (doc.exists && doc['authorID'] == userId) {
      await commentRef.delete();

      // Decrement comment count on post
      await _firestore.collection('posts').doc(postId).update({
        'commentCount': FieldValue.increment(-1),
      });
    }
  }
}
