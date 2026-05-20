import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/file/file_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PostService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  //create a new post
  Future<void> createPost(
    String content, {
    List<dynamic>? attachments,
    bool isCloseFriendsOnly = false,
    List<String>? visibleTo,
  }) async {
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
      'attachments': attachments,
      'isCloseFriendsOnly': isCloseFriendsOnly,
      'visibleTo': visibleTo ?? [],
    });
  }

  // Increment share count and record who shared it
  Future<void> incrementShareCount(String docPath, String userId) async {
    await _firestore.doc(docPath).update({
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

  //get comments future for a parent document
  Future<QuerySnapshot> getCommentsFuture(String parentPath, int limit) {
    return _firestore
        .doc(parentPath)
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

  //get posts future for a specific user
  Future<QuerySnapshot> getUserPostsFuture(String userId) {
    return _firestore
        .collection('posts')
        .where('authorID', isEqualTo: userId)
        .get();
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

  Future<void> deletePost(String postId) async {
    final userId = _auth.currentUser!.uid;
    final docRef = _firestore.collection('posts').doc(postId);
    final doc = await docRef.get();
    if (doc.exists) {
      bool isAllowed = doc['authorID'] == userId;
      if (!isAllowed) {
        final currentUserDoc = await _firestore.collection('users').doc(userId).get();
        if (currentUserDoc.exists && currentUserDoc.data()?['isAdmin'] == true) {
          isAllowed = true;
        }
      }

      if (isAllowed) {
        final data = doc.data();
        if (data != null) {
          final attachments = data['attachments'] as List<dynamic>? ?? (data['attachment'] != null ? [data['attachment']] : []);
          for (final att in attachments) {
            final objectKey = att['objectKey'] as String?;
            if (objectKey != null && objectKey.isNotEmpty) {
              await FileService().deleteAttachment(objectKey);
            }
          }
        }
        // Recursively delete all nested comments
        await _deleteSubcollection(docRef);
        await docRef.delete();
      }
    }
  }

  //add a comment to a parent document (post or comment)
  Future<void> addComment(String parentPath, String content, [List<dynamic>? attachments]) async {
    final user = _auth.currentUser!;
    final parentRef = _firestore.doc(parentPath);

    await parentRef.collection('comments').add({
      'authorID': user.uid,
      'authorUsername': user.displayName ?? 'Anonymous',
      'content': content,
      'timestamp': FieldValue.serverTimestamp(),
      'upvotes': [],
      'downvotes': [],
      'commentCount': 0,
      'shareCount': 0,
      'sharedBy': [],
      'attachments': attachments,
    });

    // Increment comment count
    await parentRef.update({
      'commentCount': FieldValue.increment(1),
    });

    // Fetch parent to send notification
    final parentDoc = await parentRef.get();
    if (parentDoc.exists) {
      final ownerID = parentDoc.data()?['authorID'] as String?;
      if (ownerID != null && ownerID != user.uid) {
        final senderUsername = user.displayName ?? 'Someone';
        await ChatService().sendPushNotification(
          ownerID,
          content,
          title: '$senderUsername replied to you',
          type: 'comment',
          extraData: {'parentPath': parentPath},
        );
      }
    }
  }

  //toggle upvote on a comment
  Future<void> upvoteComment(String commentPath) async {
    final userId = _auth.currentUser!.uid;
    final docRef = _firestore.doc(commentPath);

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
  Future<void> downvoteComment(String commentPath) async {
    final userId = _auth.currentUser!.uid;
    final docRef = _firestore.doc(commentPath);

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

  Future<void> deleteComment(String commentPath) async {
    final userId = _auth.currentUser!.uid;
    final commentRef = _firestore.doc(commentPath);

    final doc = await commentRef.get();
    if (doc.exists) {
      bool isAllowed = doc['authorID'] == userId;
      if (!isAllowed) {
        final currentUserDoc = await _firestore.collection('users').doc(userId).get();
        if (currentUserDoc.exists && currentUserDoc.data()?['isAdmin'] == true) {
          isAllowed = true;
        }
      }

      if (isAllowed) {
        final data = doc.data();
        if (data != null) {
          final attachments = data['attachments'] as List<dynamic>? ?? (data['attachment'] != null ? [data['attachment']] : []);
          for (final att in attachments) {
            final objectKey = att['objectKey'] as String?;
            if (objectKey != null && objectKey.isNotEmpty) {
              await FileService().deleteAttachment(objectKey);
            }
          }
        }
        // Recursively delete all nested comments
        await _deleteSubcollection(commentRef);
        await commentRef.delete();

        // Decrement comment count on parent
        final parentRef = commentRef.parent.parent;
        if (parentRef != null) {
          await parentRef.update({
            'commentCount': FieldValue.increment(-1),
          });
        }
      }
    }
  }

  /// Recursively deletes all documents in the 'comments' subcollection
  /// of [parentRef], including their own nested subcollections.
  Future<void> _deleteSubcollection(DocumentReference parentRef) async {
    final commentsRef = parentRef.collection('comments');
    
    // Process in batches of 100 to avoid memory issues
    QuerySnapshot snapshot;
    do {
      snapshot = await commentsRef.limit(100).get();
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          final attachments = data['attachments'] as List<dynamic>? ?? (data['attachment'] != null ? [data['attachment']] : []);
          for (final att in attachments) {
            final objectKey = att['objectKey'] as String?;
            if (objectKey != null && objectKey.isNotEmpty) {
              await FileService().deleteAttachment(objectKey);
            }
          }
        }
        // Recurse into this comment's own subcollection first
        await _deleteSubcollection(doc.reference);
        await doc.reference.delete();
      }
    } while (snapshot.docs.isNotEmpty);
  }
  
  //share a comment
  Future<void> shareComment(String commentPath) async {
    final userId = _auth.currentUser!.uid;
    final docRef = _firestore.doc(commentPath);
    await docRef.update({
      'shareCount': FieldValue.increment(1),
      'sharedBy': FieldValue.arrayUnion([userId]),
    });
  }

  Future<Map<String, String>> _reporterReasonEntry(String reason) async {
    final user = _auth.currentUser!;
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final username =
        userDoc.data()?['username'] as String? ?? user.displayName ?? 'Anonymous';
    return {
      'userId': user.uid,
      'username': username,
      'reason': reason.trim(),
    };
  }

  // Report a post
  Future<void> reportPost({
    required String postId,
    required String content,
    required String authorId,
    required String authorUsername,
    required String reason,
    List<String>? attachmentTypes,
  }) async {
    final user = _auth.currentUser!;
    final reasonEntry = await _reporterReasonEntry(reason);

    // Check for an existing pending report for this post
    final existing = await _firestore.collection('reports')
        .where('postId', isEqualTo: postId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final reportDoc = existing.docs.first;
      await reportDoc.reference.update({
        'reportCount': FieldValue.increment(1),
        'reportedByIds': FieldValue.arrayUnion([user.uid]),
        'reporterReasons': FieldValue.arrayUnion([reasonEntry]),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } else {
      await _firestore.collection('reports').add({
        'postId': postId,
        'postContent': content,
        'postAuthorId': authorId,
        'postAuthorUsername': authorUsername,
        'reportedById': user.uid,
        'reportedByIds': [user.uid],
        'reportedByUsername': reasonEntry['username'],
        'reportReason': reasonEntry['reason'],
        'reporterReasons': [reasonEntry],
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'type': 'post',
        'attachmentTypes': attachmentTypes ?? [],
        'reportCount': 1,
      });
    }

    await _firestore.collection('users').doc(authorId).update({
      'reportsCount': FieldValue.increment(1),
    });
  }

  // Report a comment
  Future<void> reportComment({
    required String commentId,
    required String commentPath,
    required String content,
    required String authorId,
    required String authorUsername,
    required String reason,
    List<String>? attachmentTypes,
  }) async {
    final user = _auth.currentUser!;
    final reasonEntry = await _reporterReasonEntry(reason);

    // Check for an existing pending report for this comment
    final existing = await _firestore.collection('reports')
        .where('commentPath', isEqualTo: commentPath)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final reportDoc = existing.docs.first;
      await reportDoc.reference.update({
        'reportCount': FieldValue.increment(1),
        'reportedByIds': FieldValue.arrayUnion([user.uid]),
        'reporterReasons': FieldValue.arrayUnion([reasonEntry]),
        'timestamp': FieldValue.serverTimestamp(),
      });
    } else {
      await _firestore.collection('reports').add({
        'commentId': commentId,
        'commentPath': commentPath,
        'commentContent': content,
        'commentAuthorId': authorId,
        'commentAuthorUsername': authorUsername,
        'reportedById': user.uid,
        'reportedByIds': [user.uid],
        'reportedByUsername': reasonEntry['username'],
        'reportReason': reasonEntry['reason'],
        'reporterReasons': [reasonEntry],
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'type': 'comment',
        'attachmentTypes': attachmentTypes ?? [],
        'reportCount': 1,
      });
    }

    await _firestore.collection('users').doc(authorId).update({
      'reportsCount': FieldValue.increment(1),
    });
  }
}
