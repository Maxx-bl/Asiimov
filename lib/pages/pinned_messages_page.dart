import 'package:asiimov/components/chat_bubble.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/encryption/encryption_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class PinnedMessagesPage extends StatefulWidget {
  final String receiverID;
  final String receiverUsername;
  final bool isGroup;

  const PinnedMessagesPage({
    super.key,
    required this.receiverID,
    required this.receiverUsername,
    this.isGroup = false,
  });

  @override
  State<PinnedMessagesPage> createState() => _PinnedMessagesPageState();
}

class _PinnedMessagesPageState extends State<PinnedMessagesPage> {
  final AuthService _authService = AuthService();
  final EncryptionService _encryptionService = EncryptionService(dotenv.env['ENCRYPTION_KEY'] ?? '');

  late Stream<QuerySnapshot> _pinnedMessagesStream;

  @override
  void initState() {
    super.initState();
    final currentUserId = _authService.getCurrentUser()!.uid;
    String chatRoomID;
    if (widget.isGroup) {
      chatRoomID = widget.receiverID;
    } else {
      List<String> ids = [currentUserId, widget.receiverID];
      ids.sort();
      chatRoomID = ids.join('_');
    }

    _pinnedMessagesStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomID)
        .collection('messages')
        .where('isPinned', isEqualTo: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('pinned_messages'.tr()),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _pinnedMessagesStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('error_loading_pinned_messages'.tr()));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          final messages = snapshot.data?.docs ?? [];
          if (messages.isEmpty) {
            return Center(child: Text('no_pinned_messages'.tr()));
          }

          // Sort locally to avoid needing a composite index in Firestore
          messages.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = aData['timestamp'] as Timestamp?;
            final bTime = bData['timestamp'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime); // Descending
          });

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final doc = messages[index];
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

              final String decryptedMessage =
                  _encryptionService.decrypt(data['message']);

              final isCurrentUser = data['senderID'] == _authService.getCurrentUser()!.uid;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ChatBubble(
                  message: decryptedMessage,
                  isCurrentUser: isCurrentUser,
                  messageId: doc.id,
                  userId: data['senderID'],
                  currentUserId: _authService.getCurrentUser()!.uid,
                  otherUserId: widget.receiverID,
                  timestamp: data['timestamp'] as Timestamp?,
                  isPinned: true,
                  isEdited: data['isEdited'] == true,
                  isGroup: widget.isGroup,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
