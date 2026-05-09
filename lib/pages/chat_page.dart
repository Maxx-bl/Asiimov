import 'package:asiimov/components/chat_bubble.dart';
import 'package:asiimov/components/my_textfield.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/encryption/encryption_service.dart';
import 'package:asiimov/services/notifications/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ChatPage extends StatefulWidget {
  final String receiverUsername;
  final String receiverID;

  const ChatPage(
      {super.key, required this.receiverUsername, required this.receiverID});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  //text controller
  final TextEditingController messageController = TextEditingController();

  //services
  final AuthService authService = AuthService();
  final ChatService chatService = ChatService();
  final EncryptionService encryptionService =
      EncryptionService(dotenv.env['ENCRYPTION_KEY'] ?? '');

  // textfield focus
  FocusNode myFocusNode = FocusNode();

  // Reply state
  String? _replyToMessageId;
  String? _replyToMessage;
  String? _replyToSenderID;

  @override
  void initState() {
    super.initState();
    // Mute notifications for this conversation
    NotificationService().setActiveChatUser(widget.receiverID);
    chatService.cleanUpOldMessages(widget.receiverID);
    myFocusNode.addListener(() {
      if (myFocusNode.hasFocus) {
        //delay keyboard time to show up
        Future.delayed(
          const Duration(milliseconds: 500),
          () => scrollDown(),
        );
      }
    });

    Future.delayed(
      const Duration(milliseconds: 500),
      () => scrollDown(),
    );
  }

  @override
  void dispose() {
    // Re-enable notifications when leaving the chat
    NotificationService().setActiveChatUser(null);
    myFocusNode.dispose();
    messageController.dispose();
    super.dispose();
  }

  //scroll down methode
  final ScrollController scrollController = ScrollController();
  void scrollDown() {
    if (scrollController.hasClients) {
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(seconds: 1),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  //set reply
  void setReplyTo(String messageId, String message, String senderID) {
    setState(() {
      _replyToMessageId = messageId;
      _replyToMessage = message;
      _replyToSenderID = senderID;
    });
    // Delay focus to ensure the UI has settled after swipe animation
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) myFocusNode.requestFocus();
    });
  }

  //cancel reply
  void cancelReply() {
    setState(() {
      _replyToMessageId = null;
      _replyToMessage = null;
      _replyToSenderID = null;
    });
  }

  //send message
  void sendMessage() async {
    if (messageController.text.isNotEmpty) {
      await chatService.sendMessage(
        widget.receiverID,
        messageController.text,
        replyToMessageId: _replyToMessageId,
        replyToMessage: _replyToMessage,
        replyToSenderID: _replyToSenderID,
      );
      messageController.clear();
      cancelReply();
    }
    scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfilePage(
                  userId: widget.receiverID,
                  username: widget.receiverUsername,
                ),
              ),
            );
          },
          child: Text('@${widget.receiverUsername}'),
        ),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Column(
        children: [
          Expanded(
            child: buildMessageList(),
          ),
          // Reply banner
          if (_replyToMessage != null) buildReplyBanner(),
          buildUserInput(),
        ],
      ),
    );
  }

  Widget buildReplyBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        border: const Border(
          top: BorderSide(color: Colors.orange, width: 2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _replyToSenderID == authService.getCurrentUser()!.uid
                      ? 'Replying to yourself'
                      : 'Replying to @${widget.receiverUsername}',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _replyToMessage!.length > 50
                      ? '${_replyToMessage!.substring(0, 50)}...'
                      : _replyToMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: cancelReply,
            child: Icon(Icons.close,
                size: 20, color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget buildMessageList() {
    String senderID = authService.getCurrentUser()!.uid;
    return StreamBuilder(
      stream: chatService.getMessages(widget.receiverID, senderID),
      builder: (context, snapshot) {
        //errors
        if (snapshot.hasError) {
          return const Text("Error");
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        //mark messages as read when loaded
        chatService.markMessagesAsRead(widget.receiverID);
        return ListView(
          controller: scrollController,
          children:
              snapshot.data!.docs.map((doc) => buildMessageItem(doc)).toList(),
        );
      },
    );
  }

  Widget buildMessageItem(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    //display message based on sender
    final currentUid = authService.getCurrentUser()!.uid;
    bool isCurrentUser = data['senderID'] == currentUid;

    String decryptedMessage;
    try {
      decryptedMessage = encryptionService.decrypt(data['message']);
    } catch (e) {
      decryptedMessage = data['message'];
    }

    // Decrypt reply preview
    String? decryptedReply;
    if (data['replyToMessage'] != null) {
      try {
        decryptedReply = encryptionService.decrypt(data['replyToMessage']);
      } catch (e) {
        decryptedReply = data['replyToMessage'];
      }
    }

    // Parse reactions
    Map<String, String>? reactions;
    if (data['reactions'] != null) {
      reactions = Map<String, String>.from(data['reactions'] as Map);
    }

    return ChatBubble(
      message: decryptedMessage,
      isCurrentUser: isCurrentUser,
      messageId: doc.id,
      userId: data['senderID'],
      currentUserId: currentUid,
      replyToMessage: decryptedReply,
      replyToSenderID: data['replyToSenderID'],
      reactions: reactions,
      onSwipeReply: () {
        setReplyTo(doc.id, decryptedMessage, data['senderID']);
      },
      onReact: (emoji) {
        myFocusNode.unfocus();
        chatService.addReaction(widget.receiverID, doc.id, emoji);
        // Ensure keyboard stays closed after popup closes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) myFocusNode.unfocus();
        });
      },
    );
  }

  Widget buildUserInput() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 50),
      child: Row(children: [
        Expanded(
            child: MyTextField(
                hintText: 'Message...',
                obscureText: false,
                focusNode: myFocusNode,
                controller: messageController)),
        Container(
            decoration: const BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
            ),
            margin: const EdgeInsets.only(right: 25),
            child: IconButton(
              onPressed: sendMessage,
              icon: const Icon(Icons.arrow_upward, color: Colors.white),
            ))
      ]),
    );
  }
}
