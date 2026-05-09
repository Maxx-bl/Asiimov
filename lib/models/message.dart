import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String senderID;
  final String senderEmail;
  final String receiverID;
  final String message;
  final Timestamp timestamp;
  final bool isRead;

  // Reply fields
  final String? replyToMessageId;
  final String? replyToMessage;
  final String? replyToSenderID;

  // Reactions: {userID: emoji}
  final Map<String, String>? reactions;

  Message({
    required this.senderID,
    required this.senderEmail,
    required this.receiverID,
    required this.message,
    required this.timestamp,
    required this.isRead,
    this.replyToMessageId,
    this.replyToMessage,
    this.replyToSenderID,
    this.reactions,
  });

  //convert to map
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'senderID': senderID,
      'senderEmail': senderEmail,
      'receiverID': receiverID,
      'message': message,
      'timestamp': timestamp,
      'isRead': isRead,
    };

    if (replyToMessageId != null) {
      map['replyToMessageId'] = replyToMessageId;
      map['replyToMessage'] = replyToMessage;
      map['replyToSenderID'] = replyToSenderID;
    }

    if (reactions != null) {
      map['reactions'] = reactions;
    }

    return map;
  }
}
