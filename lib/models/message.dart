import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String senderID;
  final String senderEmail;
  final String receiverID;
  final String message;
  final Timestamp timestamp;
  final bool isRead;
  final String messageType; // 'text', 'post_share'
  final String? sharedPostId;

  // Reply fields
  final String? replyToMessageId;
  final String? replyToMessage;
  final String? replyToSenderID;
  final String? replyToSenderUsername;

  // Reactions: {userID: emoji}
  final Map<String, String>? reactions;

  // Mentions: {username: userID}
  final Map<String, String>? mentions;

  // Attachments: [{url, type, name, size, objectKey}]
  final List<dynamic>? attachments;

  // Instant Attachment: {url, type, name, size}
  final Map<String, dynamic>? instantAttachment;

  Message({
    required this.senderID,
    required this.senderEmail,
    required this.receiverID,
    required this.message,
    required this.timestamp,
    required this.isRead,
    this.messageType = 'text',
    this.sharedPostId,
    this.replyToMessageId,
    this.replyToMessage,
    this.replyToSenderID,
    this.replyToSenderUsername,
    this.reactions,
    this.mentions,
    this.attachments,
    this.instantAttachment,
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
      'messageType': messageType,
    };

    if (sharedPostId != null) {
      map['sharedPostId'] = sharedPostId;
    }

    if (replyToMessageId != null) {
      map['replyToMessageId'] = replyToMessageId;
      map['replyToMessage'] = replyToMessage;
      map['replyToSenderID'] = replyToSenderID;
      if (replyToSenderUsername != null) {
        map['replyToSenderUsername'] = replyToSenderUsername;
      }
    }

    if (reactions != null) {
      map['reactions'] = reactions;
    }

    if (mentions != null && mentions!.isNotEmpty) {
      map['mentions'] = mentions;
      map['mentionedIds'] = mentions!.values.toList();
    }

    if (attachments != null && attachments!.isNotEmpty) {
      map['attachments'] = attachments;
    }

    if (instantAttachment != null) {
      map['instantAttachment'] = instantAttachment;
    }

    return map;
  }
}
