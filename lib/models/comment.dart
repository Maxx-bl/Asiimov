import 'package:cloud_firestore/cloud_firestore.dart';

class Comment {
  final String id;
  final String authorID;
  final String authorUsername;
  final String content;
  final Timestamp timestamp;
  final List<String> upvotes;
  final List<String> downvotes;
  final int commentCount;
  final int shareCount;
  final List<String> sharedBy;

  Comment({
    required this.id,
    required this.authorID,
    required this.authorUsername,
    required this.content,
    required this.timestamp,
    required this.upvotes,
    required this.downvotes,
    required this.commentCount,
    required this.shareCount,
    required this.sharedBy,
  });

  int get score => upvotes.length - downvotes.length;

  factory Comment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Comment(
      id: doc.id,
      authorID: data['authorID'] ?? '',
      authorUsername: data['authorUsername'] ?? '',
      content: data['content'] ?? '',
      timestamp: data['timestamp'] ?? Timestamp.now(),
      upvotes: List<String>.from(data['upvotes'] ?? []),
      downvotes: List<String>.from(data['downvotes'] ?? []),
      commentCount: data['commentCount'] ?? 0,
      shareCount: data['shareCount'] ?? 0,
      sharedBy: List<String>.from(data['sharedBy'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorID': authorID,
      'authorUsername': authorUsername,
      'content': content,
      'timestamp': timestamp,
      'upvotes': upvotes,
      'downvotes': downvotes,
      'commentCount': commentCount,
      'shareCount': shareCount,
      'sharedBy': sharedBy,
    };
  }
}
