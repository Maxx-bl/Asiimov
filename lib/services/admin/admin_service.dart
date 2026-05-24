import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:asiimov/services/chat/chat_service.dart';

class AdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Suspend user
  Future<void> suspendUser(String userId, String reason) async {
    await _firestore.collection('users').doc(userId).update({
      'isSuspended': true,
      'suspensionReason': reason,
    });
  }

  // Unsuspend user
  Future<void> unsuspendUser(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'isSuspended': false,
      'suspensionReason': FieldValue.delete(),
    });
  }

  // Toggle official badge
  Future<void> toggleOfficialBadge(String userId, bool isOfficial) async {
    await _firestore.collection('users').doc(userId).update({
      'official': isOfficial,
    });
  }

  // Resolve a report
  Future<void> resolveReport(String reportId, {String? action, String? reason}) async {
    await _firestore.collection('reports').doc(reportId).update({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
      if (action != null) 'resolutionAction': action,
      if (reason != null) 'resolutionReason': reason,
    });
  }

  // Dismiss a ticket
  Future<void> dismissTicket(String ticketId) async {
    await _firestore.collection('tickets').doc(ticketId).update({
      'status': 'dismissed',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Reply to a ticket
  Future<void> replyToTicket(String ticketId, String text, String targetUserId, String subject) async {
    final messageData = {
      'sender': 'admin',
      'text': text,
      'timestamp': Timestamp.now(),
    };

    await _firestore.collection('tickets').doc(ticketId).update({
      'messages': FieldValue.arrayUnion([messageData]),
      'status': 'answered',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Send notification to the user
    await ChatService().sendPushNotification(
      targetUserId,
      subject, // Content is the subject
      title: 'Support',
      type: 'support',
      extraData: {'ticketId': ticketId},
    );
  }
}

