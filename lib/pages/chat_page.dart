import 'dart:async';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import 'package:asiimov/components/chat_bubble.dart';
import 'package:asiimov/components/group_icon.dart';
import 'package:asiimov/components/instant_camera_screen.dart';
import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/pages/group_settings_page.dart';
import 'package:asiimov/pages/pinned_messages_page.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/encryption/encryption_service.dart';
import 'package:asiimov/services/file/file_service.dart';
import 'package:asiimov/services/image/image_service.dart';
import 'package:asiimov/services/notifications/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ChatPage extends StatefulWidget {
  final String receiverUsername;
  final String receiverID;
  final bool isGroup;
  final String? creatorId;

  const ChatPage({
    super.key,
    required this.receiverUsername,
    required this.receiverID,
    this.isGroup = false,
    this.creatorId,
  });

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

  // Stream for live read status
  StreamSubscription? _messageSubscription;

  // Pagination state
  int _limit = 30;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    NotificationService().setActiveChatUser(widget.receiverID);
    chatService.markMessageAsRead(widget.receiverID, isGroup: widget.isGroup);
    // cleanUpOldMessages needs update in ChatService to handle group IDs correctly
    chatService.cleanUpOldMessages(widget.receiverID, isGroup: widget.isGroup);
    scrollController.addListener(_onScroll);

    // Track text input to toggle between + and send button
    messageController.addListener(() {
      final hasText = messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });

    // Listen for new messages while the page is open to mark them as read automatically
    _messageSubscription = chatService
        .getMessages(authService.getCurrentUser()!.uid, widget.receiverID, isGroup: widget.isGroup)
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final lastMessageData = snapshot.docs.first.data() as Map<String, dynamic>;
        
        // Mark as read if it's a private chat from the other user OR if it's a group chat
        if (widget.isGroup) {
          chatService.markMessageAsRead(widget.receiverID, isGroup: true);
        } else if (lastMessageData['senderID'] == widget.receiverID &&
            lastMessageData['isRead'] == false) {
          chatService.markMessageAsRead(widget.receiverID, isGroup: false);
        }
      }
    });
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
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _messageSubscription?.cancel();
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

  // Edit state
  String? _editingMessageId;
  String? _editingMessageText;

  // Audio recording state
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0;

  // Attachment state
  final FileService _fileService = FileService();
  List<File> _stagedFiles = [];
  bool _isUploading = false;
  bool _hasText = false;

  // GlobalKeys for each message to allow scrolling to them
  final Map<String, GlobalKey<ChatBubbleState>> _messageKeys = {};
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

  //set edit
  void setEditMessage(String messageId, String message) {
    cancelReply(); // Can't edit and reply at the same time
    setState(() {
      _editingMessageId = messageId;
      _editingMessageText = message;
      messageController.text = message;
    });
    // Delay focus to ensure the UI has settled
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) myFocusNode.requestFocus();
    });
  }

  //cancel edit
  void cancelEdit() {
    setState(() {
      _editingMessageId = null;
      _editingMessageText = null;
      messageController.clear();
    });
  }

  //send message
  void sendMessage() async {
    final String message = messageController.text.trim();
    if (message.isEmpty && _stagedFiles.isEmpty) return;

    if (_editingMessageId != null) {
      // Edit mode (no attachments in edit)
      final String msgId = _editingMessageId!;
      cancelEdit();
      await chatService.editMessage(
        widget.receiverID,
        msgId,
        message,
        isGroup: widget.isGroup,
      );
      return;
    }

    // Capture reply data and staged files before clearing
    final String? replyId = _replyToMessageId;
    final String? replyText = _replyToMessage;
    final String? replySender = _replyToSenderID;
    final List<File> filesToUpload = List.from(_stagedFiles);

    // Clear immediately for better UX
    messageController.clear();
    cancelReply();
    setState(() {
      _stagedFiles = [];
      _isUploading = filesToUpload.isNotEmpty;
    });

    // Upload attachments if any
    List<dynamic>? attachments;
    if (filesToUpload.isNotEmpty) {
      attachments = [];
      // Construct a chat room ID for storage path
      final currentUid = authService.getCurrentUser()!.uid;
      List<String> ids = [currentUid, widget.receiverID];
      ids.sort();
      final chatRoomId = widget.isGroup ? widget.receiverID : ids.join('_');

      for (final file in filesToUpload) {
        final result = await _fileService.uploadChatAttachment(file, chatRoomId);
        if (result != null) {
          attachments.add(result);
        }
      }
      if (mounted) setState(() => _isUploading = false);

      // If all uploads failed and no text, abort
      if (attachments.isEmpty && message.isEmpty) return;
    }

    // Send in background
    await chatService.sendMessage(
      widget.receiverID,
      message,
      isGroup: widget.isGroup,
      replyToMessageId: replyId,
      replyToMessage: replyText,
      replyToSenderID: replySender,
      attachments: attachments,
    );
  }

  // Show attachment picker bottom sheet
  void _showAttachmentPicker() {
    final parentContext = context;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Send Attachment',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: const Icon(Icons.photo_library, color: Colors.white),
                ),
                title: const Text('Photos & Videos'),
                subtitle: const Text('From your gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final files = await _fileService.pickGalleryMedia();
                    if (files.isNotEmpty && mounted) {
                      setState(() => _stagedFiles.addAll(files));
                    }
                  } catch (e) {
                    if (parentContext.mounted) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  child: const Icon(Icons.insert_drive_file, color: Colors.white),
                ),
                title: const Text('Documents'),
                subtitle: const Text('PDF, ZIP, and more'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    final files = await _fileService.pickDocuments();
                    if (files.isNotEmpty && mounted) {
                      setState(() => _stagedFiles.addAll(files));
                    }
                  } catch (e) {
                    if (parentContext.mounted) {
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: widget.isGroup
            ? Text(
                widget.receiverUsername,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              )
            : GestureDetector(
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
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PinnedMessagesPage(
                    receiverID: widget.receiverID,
                    receiverUsername: widget.receiverUsername,
                    isGroup: widget.isGroup,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.push_pin),
          ),
          if (widget.isGroup)
            IconButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GroupSettingsPage(
                      groupId: widget.receiverID,
                      groupName: widget.receiverUsername,
                      creatorId: widget.creatorId ?? '',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.settings),
            ),
        ],
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Column(
        children: [
          Expanded(
            child: buildMessageList(),
          ),
          // Upload indicator
          if (_isUploading)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor)),
                  const SizedBox(width: 8),
                  const Text('Uploading...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          // Reply or Edit banner
          if (_editingMessageId != null)
            buildEditBanner()
          else if (_replyToMessage != null)
            buildReplyBanner(),
          // Staged files preview
          if (_stagedFiles.isNotEmpty)
            _buildStagedFilesPreview(),
          buildUserInput(),
        ],
      ),
    );
  }

  Widget buildEditBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.9),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.blue,
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
                    const Icon(Icons.edit, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    const Text(
                      'Editing message',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _editingMessageText!,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: cancelEdit,
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget buildReplyBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.9),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              color: Theme.of(context).primaryColor,
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
                    Icon(Icons.reply, size: 14, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      _replyToSenderID == authService.getCurrentUser()!.uid
                          ? 'You'
                          : widget.receiverUsername,
                      style: TextStyle(
                        color: Theme.of(context).primaryColor,
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
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
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
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
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
            Icon(Icons.info_outline, color: Theme.of(context).primaryColor, size: 24),
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
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).primaryColor),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((_) => _showingInfoDialog = false);
  }

  Widget buildMessageList() {
    return StreamBuilder(
      stream: chatService.getMessagesWithLimit(
          authService.getCurrentUser()!.uid, widget.receiverID, _limit, isGroup: widget.isGroup),
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
        _loadedMessageIds = docs.map((doc) => doc.id).toList();

        // Empty conversation state — show profile picture centered like Instagram
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isGroup)
                  // Fetch group icon from Firestore
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('chats').doc(widget.receiverID).get(),
                    builder: (context, groupSnap) {
                      final groupIconUrl = groupSnap.data?.data() is Map<String, dynamic>
                          ? (groupSnap.data!.data() as Map<String, dynamic>)['groupIconUrl'] as String?
                          : null;
                      return GroupIcon(size: 120, imageUrl: groupIconUrl);
                    },
                  )
                else
                  ProfileAvatar(
                    userId: widget.receiverID,
                    username: widget.receiverUsername,
                    radius: 60,
                  ),
                const SizedBox(height: 16),
                Text(
                  widget.receiverUsername,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isGroup ? 'No messages yet in this group.' : 'No messages yet.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          );
        }

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
                            progress >= 1.0 ? Theme.of(context).primaryColor : Colors.grey.shade400,
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
                    final data = docs[index].data() as Map<String, dynamic>;
                    bool showUsername = widget.isGroup;
                    bool showAvatar = widget.isGroup;
                    
                    // Don't show username if previous message (index + 1) was from same sender
                    if (widget.isGroup && index < docs.length - 1) {
                      final prevData = docs[index + 1].data() as Map<String, dynamic>;
                      if (prevData['senderID'] == data['senderID'] && prevData['isSystemMessage'] != true) {
                        showUsername = false;
                      }
                    }

                    // Show avatar on the first (top-most) message of a consecutive sender series (same logic as username)
                    if (widget.isGroup && index < docs.length - 1) {
                      final prevData = docs[index + 1].data() as Map<String, dynamic>;
                      if (prevData['senderID'] == data['senderID'] && prevData['isSystemMessage'] != true) {
                        showAvatar = false;
                      }
                    }

                    return buildMessageItem(docs[index], isLast: index == 0, showUsername: showUsername, showAvatar: showAvatar);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget buildMessageItem(DocumentSnapshot doc, {required bool isLast, required bool showUsername, bool showAvatar = false}) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    // Handle System Messages
    if (data['isSystemMessage'] == true) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 40),
        child: Center(
          child: Text(
            data['message'],
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

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



    Widget bubble = ChatBubble(
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
      isSeen: data['isRead'] == true,
      showStatus: !widget.isGroup && isLast && isCurrentUser,
      isGroup: widget.isGroup,
      isEdited: data['isEdited'] == true,
      isPinned: data['isPinned'] == true,
      attachments: data['attachments'] as List<dynamic>?,
      instantAttachment: data['instantAttachment'] as Map<String, dynamic>?,
      onEdit: (messageId, content) {
        setEditMessage(messageId, content);
      },
      onSwipeReply: () {
        setReplyTo(messageId, decryptedMessage, data['senderID']);
      },
      onReplyTap: (repliedId) {
        _scrollToMessage(repliedId);
      },
      onReact: (emoji) {
        chatService.addReaction(widget.receiverID, messageId, emoji, isGroup: widget.isGroup);
        // Ensure keyboard stays closed after popup closes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) myFocusNode.unfocus();
        });
      },
    );

    // In group chats, show avatar next to other users' messages
    final bool showGroupAvatar = widget.isGroup && !isCurrentUser;

    return Column(
      crossAxisAlignment: isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showUsername && !isCurrentUser)
          Padding(
            padding: EdgeInsets.only(left: showGroupAvatar ? 48 : 25, bottom: 2, top: 8),
            child: Text(
              '@${data['senderUsername'] ?? 'unknown'}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        if (showGroupAvatar)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 6),
                child: showAvatar
                    ? ProfileAvatar(
                        userId: data['senderID'],
                        username: data['senderUsername'] ?? '?',
                        radius: 16,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfilePage(
                                userId: data['senderID'],
                                username: data['senderUsername'] ?? '',
                              ),
                            ),
                          );
                        },
                      )
                    : const SizedBox(width: 32), // invisible spacer to keep alignment
              ),
              const SizedBox(width: 6),
              Expanded(child: bubble),
            ],
          )
        else
          bubble,
      ],
    );
  }

  Widget _buildStagedFilesPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surface,
      child: SizedBox(
        height: 72,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _stagedFiles.length,
          itemBuilder: (context, index) {
            final file = _stagedFiles[index];
            final ext = file.path.split('.').last.toLowerCase();
            final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
            final isVideo = ['mp4', 'mov', 'avi', 'mkv'].contains(ext);

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Theme.of(context).colorScheme.secondary,
                      border: Border.all(color: Colors.grey.shade400, width: 0.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: isImage
                          ? Image.file(file, fit: BoxFit.cover)
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isVideo ? Icons.videocam : Icons.insert_drive_file,
                                    color: Theme.of(context).primaryColor,
                                    size: 24,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    ext.toUpperCase(),
                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                  // Remove button
                  Positioned(
                    top: -2,
                    right: -2,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _stagedFiles.removeAt(index));
                      },
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openInstantCamera() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const InstantCameraScreen()),
    );
    if (result == null) return;

    final File file = result['file'];
    final bool isVideo = result['isVideo'];

    setState(() => _isUploading = true);

    File? compressedFile;
    if (isVideo) {
      compressedFile = file;
    } else {
      compressedFile = await ImageService().compressImage(file, quality: 75, minWidth: 800, minHeight: 800);
    }

    final fileToUpload = compressedFile ?? file;
    
    final currentUid = authService.getCurrentUser()!.uid;
    List<String> ids = [currentUid, widget.receiverID];
    ids.sort();
    final chatRoomId = widget.isGroup ? widget.receiverID : ids.join('_');

    final uploadResult = await _fileService.uploadChatAttachment(fileToUpload, chatRoomId);
    if (mounted) setState(() => _isUploading = false);

    if (uploadResult == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload attachment.')),
        );
      }
      return;
    }

    final instantAttachment = {
      'name': fileToUpload.path.split('/').last,
      'url': uploadResult['url'],
      'type': isVideo ? 'video' : 'image',
      'size': await fileToUpload.length(),
      'objectKey': uploadResult['objectKey'],
    };

    await chatService.sendMessage(
      widget.receiverID,
      isVideo ? '📸 Instant Video' : '📸 Instant Photo',
      isGroup: widget.isGroup,
      messageType: 'instant_attachment',
      instantAttachment: instantAttachment,
    );
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        setState(() {
          _isRecording = true;
          _recordingDuration = 0;
        });
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (_recordingDuration >= 60) {
            _stopRecordingAndSend();
          } else {
            setState(() {
              _recordingDuration++;
            });
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    if (_isRecording) {
      await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
        _recordingDuration = 0;
      });
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    final int recordedDuration = _recordingDuration;
    final path = await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _recordingDuration = 0;
    });

    if (path == null) return;
    final file = File(path);
    final length = await file.length();
    if (length < 1000) return; // ignore accidental very short clicks

    setState(() => _isUploading = true);

    final uploadResult = await _fileService.uploadChatAttachment(file, 'voice');
    if (mounted) setState(() => _isUploading = false);

    if (uploadResult == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload voice message.')),
        );
      }
      return;
    }

    final instantAttachment = {
      'name': file.path.split('/').last,
      'url': uploadResult['url'],
      'type': 'audio',
      'size': length,
      'duration': recordedDuration,
      'objectKey': uploadResult['objectKey'],
    };

    await chatService.sendMessage(
      widget.receiverID,
      '🎤 Voice Message',
      isGroup: widget.isGroup,
      messageType: 'instant_attachment',
      instantAttachment: instantAttachment,
    );
  }

  Widget buildUserInput() {
    final bool showSendButton = _hasText || _stagedFiles.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                      color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.3),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: _isRecording
                      ? Row(
                          children: [
                            const Icon(Icons.mic, color: Colors.redAccent, size: 24),
                            const SizedBox(width: 12),
                            Text(
                              '${(_recordingDuration ~/ 60).toString().padLeft(2, '0')}:${(_recordingDuration % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: _cancelRecording,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text('Cancel', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            if (!_hasText) ...[
                              GestureDetector(
                                onTap: _openInstantCamera,
                                child: Icon(Icons.camera_alt_rounded, color: Theme.of(context).primaryColor, size: 24),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: TextField(
                                controller: messageController,
                                focusNode: myFocusNode,
                                maxLines: 4,
                                minLines: 1,
                                maxLength: 1000,
                                buildCounter: (context, {required currentLength, required isFocused, maxLength}) {
                                  if (currentLength < 900) return null;
                                  return Text(
                                    '$currentLength / $maxLength',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                    ),
                                  );
                                },
                                textInputAction: TextInputAction.newline,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText: _stagedFiles.isNotEmpty ? 'Add a caption...' : 'Message...',
                                  hintStyle: TextStyle(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                ),
                                style: TextStyle(
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 8),
              if (_isRecording)
                GestureDetector(
                  onTap: _stopRecordingAndSend,
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
                  ),
                )
              else if (showSendButton)
                GestureDetector(
                  onTap: sendMessage,
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                    child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 26),
                  ),
                )
              else ...[
                GestureDetector(
                  onTap: _showAttachmentPicker,
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(color: Colors.grey.shade600, shape: BoxShape.circle),
                    child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _startRecording(),
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                    child: const Icon(Icons.mic, color: Colors.white, size: 26),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
