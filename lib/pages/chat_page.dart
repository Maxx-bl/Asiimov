import 'dart:async';

import 'package:asiimov/components/chat_bubble.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/encryption/encryption_service.dart';
import 'package:asiimov/services/notifications/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rxdart/rxdart.dart';

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

  // scroll controller — using reverse ListView so index 0 = newest
  final ScrollController scrollController = ScrollController();

  // Pagination state
  int _limit = 30;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    NotificationService().setActiveChatUser(widget.receiverID);
    chatService.markMessagesAsRead(widget.receiverID);
    chatService.cleanUpOldMessages(widget.receiverID);
    scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // Since reverse: true, scroll top is actually maxScrollExtent
    if (scrollController.hasClients && 
        scrollController.position.pixels >= scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore) {
        setState(() {
          _isLoadingMore = true;
          _limit += 30;
        });
        // Tiny delay to reset the flag after the stream has time to update
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) setState(() => _isLoadingMore = false);
        });
      }
    }
  }

  @override
  void dispose() {
    NotificationService().setActiveChatUser(null);
    scrollController.removeListener(_onScroll);
    myFocusNode.dispose();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }

  // Reply state
  String? _replyToMessageId;
  String? _replyToMessage;
  String? _replyToSenderID;

  // GlobalKeys for each message to allow scrolling to them
  final Map<String, GlobalKey<ChatBubbleState>> _messageKeys = {};
  int _totalMessagesLoaded = 0;
  List<String> _loadedMessageIds = [];

  // Scroll to a specific message by ID
  void _scrollToMessage(String messageId, {int retryCount = 0}) {
    final key = _messageKeys[messageId];

    if (key != null && key.currentContext != null) {
      // Message found and rendered
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOutQuart,
        alignment: 1.0, // Top
      );

      Future.delayed(const Duration(milliseconds: 650), () {
        key.currentState?.flash();
      });
    } else {
      // Not rendered yet. Check if it's at least loaded in memory
      int index = _loadedMessageIds.indexOf(messageId);

      if (index != -1 && retryCount < 2) {
        // It's in memory but off-screen. 
        // Quick jump to force rendering
        double estimatedOffset = (index * 110.0).clamp(
          scrollController.offset,
          scrollController.position.maxScrollExtent,
        );

        scrollController.animateTo(
          estimatedOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );

        // One quick retry to see if it's rendered now
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted) _scrollToMessage(messageId, retryCount: retryCount + 1);
        });
      } else {
        // Not loaded in current view or deleted
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Message unavailable or too old"),
            duration: Duration(seconds: 2),
          ),
        );
      }
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
    final String message = messageController.text.trim();
    if (message.isNotEmpty) {
      // Capture reply data before clearing
      final String? replyId = _replyToMessageId;
      final String? replyText = _replyToMessage;
      final String? replySender = _replyToSenderID;

      // Clear immediately for better UX
      messageController.clear();
      cancelReply();

      // Send in background
      await chatService.sendMessage(
        widget.receiverID,
        message,
        replyToMessageId: replyId,
        replyToMessage: replyText,
        replyToSenderID: replySender,
      );
    }
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
          child: UsernameDisplay(
            userId: widget.receiverID,
            username: widget.receiverUsername,
            style: const TextStyle(fontSize: 20),
            iconSize: 20,
          ),
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
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withOpacity(0.9),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.reply, size: 14, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      _replyToSenderID == authService.getCurrentUser()!.uid
                          ? 'You'
                          : widget.receiverUsername,
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _replyToMessage!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: cancelReply,
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // Overscroll pull-to-info state
  double _overscrollAmount = 0.0;
  static const double _overscrollThreshold = 250.0; // 2.5x longer pull
  bool _showingInfoDialog = false;
  bool _isPulling = false; // Track sustained pull vs flick

  /// Show the message deletion info dialog
  // ──────────────────────────────────────────────
  // 📝 TO CHANGE THE INFO TEXT: Edit the string below
  // ──────────────────────────────────────────────
  void _showDeletionInfoDialog() {
    if (_showingInfoDialog) return;
    _showingInfoDialog = true;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            const Text(
              'Private Messages',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Messages are automatically deleted after 24 hours once they have been read, '
          'unless they are among the 30 most recent messages in the conversation.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((_) => _showingInfoDialog = false);
  }

  Widget buildMessageList() {
    String senderID = authService.getCurrentUser()!.uid;
    return StreamBuilder(
      stream: chatService.getMessagesWithLimit(
          widget.receiverID, senderID, _limit),
      builder: (context, snapshot) {
        //errors
        if (snapshot.hasError) {
          return const Center(child: Text("Error"));
        }

        //loading (Only show if no data yet)
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        //return listview
        final docs = snapshot.data?.docs ?? [];
        _totalMessagesLoaded = docs.length;
        _loadedMessageIds = docs.map((doc) => doc.id).toList();

        // Calculate how much to push the content down (capped at 80px visual displacement)
        final double displacement = (_overscrollAmount / _overscrollThreshold * 80).clamp(0.0, 80.0);
        final double progress = (_overscrollAmount / _overscrollThreshold).clamp(0.0, 1.0);

        return Column(
          children: [
            // Indicator area that pushes content down (native refresh feel)
            AnimatedContainer(
              duration: _isPulling ? Duration.zero : const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              height: displacement,
              child: displacement > 10
                  ? Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress >= 1.0 ? Colors.orange : Colors.grey.shade400,
                          ),
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            // Message list
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is OverscrollNotification) {
                    // In reverse mode, overscroll > 0 = top of conversation
                    // Ignore small flicks (< 2px per event)
                    if (notification.overscroll > 2.0) {
                      _isPulling = true;
                      setState(() {
                        _overscrollAmount = (_overscrollAmount + notification.overscroll * 0.5)
                            .clamp(0.0, _overscrollThreshold);
                      });
                    }
                  } else if (notification is ScrollEndNotification) {
                    if (_overscrollAmount >= _overscrollThreshold) {
                      _showDeletionInfoDialog();
                    }
                    _isPulling = false;
                    setState(() => _overscrollAmount = 0.0);
                  } else if (notification is ScrollUpdateNotification) {
                    // Reset overscroll if user scrolls back down
                    if (_overscrollAmount > 0 && (notification.scrollDelta ?? 0) < -1) {
                      _isPulling = false;
                      setState(() => _overscrollAmount = 0.0);
                    }
                  }
                  return false;
                },
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: docs.length,
                  reverse: true,
                  itemBuilder: (context, index) {
                    return buildMessageItem(docs[index], index == 0);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget buildMessageItem(DocumentSnapshot doc, bool isLast) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // Ensure we have a GlobalKey for this message ID for scrolling
    final messageId = doc.id;
    final key =
        _messageKeys.putIfAbsent(messageId, () => GlobalKey<ChatBubbleState>());

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

    bool showSeen = isLast && isCurrentUser && (data['isRead'] == true);

    return ChatBubble(
      key: key,
      message: decryptedMessage,
      isCurrentUser: isCurrentUser,
      messageId: messageId,
      userId: data['senderID'],
      currentUserId: currentUid,
      otherUserId: widget.receiverID,
      messageType: data['messageType'] ?? 'text',
      sharedPostId: data['sharedPostId'],
      replyToMessageId: data['replyToMessageId'],
      replyToMessage: decryptedReply,
      replyToSenderID: data['replyToSenderID'],
      reactions: reactions,
      timestamp: data['timestamp'] as Timestamp?,
      showSeen: showSeen,
      onSwipeReply: () {
        setReplyTo(messageId, decryptedMessage, data['senderID']);
      },
      onReplyTap: (repliedId) {
        _scrollToMessage(repliedId);
      },
      onReact: (emoji) {
        myFocusNode.unfocus();
        chatService.addReaction(widget.receiverID, messageId, emoji);
        // Ensure keyboard stays closed after popup closes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) myFocusNode.unfocus();
        });
      },
    );
  }

  Widget buildUserInput() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.tertiary.withOpacity(0.3),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: messageController,
                    focusNode: myFocusNode,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle: TextStyle(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: sendMessage,
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 26),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
