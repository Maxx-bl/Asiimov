import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:asiimov/services/encryption/encryption_service.dart';

class Post {
  final String id;
  final String authorID;
  final String authorUsername;
  final String content;
  final String rawEncryptedContent;
  final int encryptionVersion; // 1 = global key, 2 = per-post RSA E2EE
  final Timestamp timestamp;
  final List<String> upvotes;
  final List<String> downvotes;
  final int commentCount;
  final int shareCount;
  final List<String> sharedBy;
  final List<dynamic>? attachments;
  final bool isCloseFriendsOnly;
  final List<String> visibleTo;

  Post({
    required this.id,
    required this.authorID,
    required this.authorUsername,
    required this.content,
    this.rawEncryptedContent = '',
    this.encryptionVersion = 1,
    required this.timestamp,
    required this.upvotes,
    required this.downvotes,
    required this.commentCount,
    required this.shareCount,
    required this.sharedBy,
    this.attachments,
    this.isCloseFriendsOnly = false,
    this.visibleTo = const [],
  });

  int get score => upvotes.length - downvotes.length;

  /// Returns a copy of this post with decrypted content (used after async E2EE decrypt).
  Post withDecryptedContent(String decrypted) => Post(
        id: id,
        authorID: authorID,
        authorUsername: authorUsername,
        content: decrypted,
        rawEncryptedContent: rawEncryptedContent,
        encryptionVersion: encryptionVersion,
        timestamp: timestamp,
        upvotes: upvotes,
        downvotes: downvotes,
        commentCount: commentCount,
        shareCount: shareCount,
        sharedBy: sharedBy,
        attachments: attachments,
        isCloseFriendsOnly: isCloseFriendsOnly,
        visibleTo: visibleTo,
      );

  factory Post.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final encryption = EncryptionService(dotenv.env['ENCRYPTION_KEY'] ?? '');

    final int version = (data['encryptionVersion'] as int?) ?? 1;
    String rawContent = data['content'] ?? '';
    String decryptedContent = rawContent;

    if (version == 1 && EncryptionService.isEncrypted(rawContent)) {
      try {
        decryptedContent = encryption.decrypt(rawContent);
      } catch (_) {
        decryptedContent = rawContent;
      }
    }
    // version == 2: E2EE post — content stays encrypted until PostKeyService decrypts it asynchronously

    return Post(
      id: doc.id,
      authorID: data['authorID'] ?? '',
      authorUsername: data['authorUsername'] ?? '',
      content: version == 1 ? decryptedContent : '',
      rawEncryptedContent: rawContent,
      encryptionVersion: version,
      timestamp: data['timestamp'] ?? Timestamp.now(),
      upvotes: List<String>.from(data['upvotes'] ?? []),
      downvotes: List<String>.from(data['downvotes'] ?? []),
      commentCount: data['commentCount'] ?? 0,
      shareCount: data['shareCount'] ?? 0,
      sharedBy: List<String>.from(data['sharedBy'] ?? []),
      attachments: data['attachments'] as List<dynamic>? ??
          (data['attachment'] != null ? [data['attachment']] : null),
      isCloseFriendsOnly: data['isCloseFriendsOnly'] ?? false,
      visibleTo: List<String>.from(data['visibleTo'] ?? []),
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
      'attachments': attachments,
      'isCloseFriendsOnly': isCloseFriendsOnly,
      'visibleTo': visibleTo,
    };
  }
}
