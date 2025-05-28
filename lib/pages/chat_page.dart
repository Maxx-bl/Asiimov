import 'package:asiimov/components/chat_bubble.dart';
import 'package:asiimov/components/my_textfield.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/encryption/encryption_service.dart';
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

  // textfield focus
  FocusNode myFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
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
    myFocusNode.dispose();
    messageController.dispose();
    super.dispose();
  }

  //scroll down methode
  final ScrollController scrollController = ScrollController();
  void scrollDown() {
    scrollController.animateTo(
      scrollController.position.maxScrollExtent,
      duration: const Duration(seconds: 1),
      curve: Curves.fastOutSlowIn,
    );
  }

  //send message
  void sendMessage() async {
    if (messageController.text.isNotEmpty) {
      await chatService.sendMessage(widget.receiverID, messageController.text);
      messageController.clear();
    }
    scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('@${widget.receiverUsername}'),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Column(
        children: [
          Expanded(
            child: buildMessageList(),
          ),
          buildUserInput(),
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
    bool isCurrentUser = data['senderID'] == authService.getCurrentUser()!.uid;
    var alignment =
        isCurrentUser ? Alignment.centerRight : Alignment.centerLeft;

    final encryptionService =
        EncryptionService(dotenv.env['ENCRYPTION_KEY'] ?? '');

    String decryptedMessage;
    try {
      decryptedMessage = encryptionService.decrypt(data['message']);
    } catch (e) {
      decryptedMessage = data['message'];
    }

    return Container(
      alignment: alignment,
      child: ChatBubble(
        message: decryptedMessage,
        isCurrentUser: isCurrentUser,
        messageId: doc.id,
        userId: data['senderID'],
      ),
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
