import 'package:asiimov/components/chat_bubble.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/encryption/conversation_key_service.dart';
import 'package:asiimov/services/encryption/encryption_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
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

  late final String _chatRoomId;
  enc.Key? _conversationKey;
  late Stream<QuerySnapshot> _pinnedMessagesStream;

  @override
  void initState() {
    super.initState();
    final currentUserId = _authService.getCurrentUser()!.uid;
    if (widget.isGroup) {
      _chatRoomId = widget.receiverID;
    } else {
      final ids = [currentUserId, widget.receiverID]..sort();
      _chatRoomId = ids.join('_');
    }

    _pinnedMessagesStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatRoomId)
        .collection('messages')
        .where('isPinned', isEqualTo: true)
        .snapshots();

    _loadConversationKey(currentUserId);
  }

  Future<void> _loadConversationKey(String currentUserId) async {
    try {
      List<String> participantIds;
      if (widget.isGroup) {
        final groupDoc = await FirebaseFirestore.instance.collection('chats').doc(_chatRoomId).get();
        participantIds = List<String>.from(groupDoc.data()?['members'] ?? []);
      } else {
        participantIds = [currentUserId, widget.receiverID];
      }
      final key = await ConversationKeyService.getOrCreateConversationKey(_chatRoomId, participantIds);
      if (mounted) setState(() => _conversationKey = key);
    } catch (_) {}
  }

  String _decryptMessage(String encrypted) {
    if (encrypted.isEmpty) return '';
    if (_conversationKey != null) {
      try {
        return EncryptionService.decryptWithKey(encrypted, _conversationKey!);
      } catch (_) {}
    }
    try {
      return _encryptionService.decrypt(encrypted);
    } catch (_) {
      return '';
    }
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

          messages.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aTime = aData['timestamp'] as Timestamp?;
            final bTime = bData['timestamp'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final doc = messages[index];
              final data = doc.data() as Map<String, dynamic>;
              final decryptedMessage = _decryptMessage(data['message'] as String? ?? '');
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
