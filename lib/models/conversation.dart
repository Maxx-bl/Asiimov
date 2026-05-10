import 'package:cloud_firestore/cloud_firestore.dart';

class Conversation {
  final Map<String, dynamic> userData;
  final Map<String, dynamic>? lastMessage;
  final int unreadCount;
  final DateTime lastActive;

  Conversation({
    required this.userData,
    this.lastMessage,
    required this.unreadCount,
    required this.lastActive,
  });

  String get otherUserId => userData['uid'] ?? '';
  String get otherUsername => userData['username'] ?? 'Unknown';
}
