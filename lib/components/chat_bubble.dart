import 'package:asiimov/models/post.dart';
import 'package:asiimov/pages/post_detail_page.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/themes/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatBubble extends StatefulWidget {
  final String message;
  final bool isCurrentUser;
  final String messageId;
  final String userId;
  final String? replyToMessage;
  final String? replyToSenderID;
  final String currentUserId;
  final String otherUserId;
  final String messageType;
  final String? sharedPostId;
  final Map<String, String>? reactions;
  final Timestamp? timestamp;
  final bool showSeen;
  final void Function(String emoji)? onReact;
  final VoidCallback? onSwipeReply;

  const ChatBubble({
    super.key,
    required this.message,
    required this.isCurrentUser,
    required this.messageId,
    required this.userId,
    required this.currentUserId,
    required this.otherUserId,
    this.messageType = 'text',
    this.sharedPostId,
    this.replyToMessage,
    this.replyToSenderID,
    this.reactions,
    this.timestamp,
    this.showSeen = false,
    this.onReact,
    this.onSwipeReply,
  });

  static const List<String> quickEmojis = ['❤️', '😂', '😮', '😢', '😡', '👍'];

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool _replyTriggered = false;
  static const double _maxDrag = 80;
  static const double _triggerThreshold = 60;

  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (details.delta.dx < 0 && _dragOffset <= 0) return; // no left swipe from rest
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(0.0, _maxDrag);
      // Set triggered when reaching threshold
      if (_dragOffset >= _triggerThreshold) {
        _replyTriggered = true;
      }
      // Cancel if user pulls back below threshold
      if (_dragOffset < _triggerThreshold) {
        _replyTriggered = false;
      }
    });
  }

  void _onDragEnd(DragEndDetails details) {
    // Only fire reply if still past threshold when finger lifts
    if (_replyTriggered && _dragOffset >= _triggerThreshold) {
      widget.onSwipeReply?.call();
    }
    _replyTriggered = false;

    // Animate back to 0
    final startOffset = _dragOffset;
    _animController.reset();
    _animController.addListener(_animListener(startOffset));
    _animController.forward();
  }

  VoidCallback _animListener(double startOffset) {
    late VoidCallback listener;
    listener = () {
      if (mounted) {
        setState(() {
          _dragOffset =
              startOffset * (1 - Curves.easeOut.transform(_animController.value));
        });
      }
      if (_animController.isCompleted) {
        _animController.removeListener(listener);
      }
    };
    return listener;
  }

  void showDeleteOptions(BuildContext context, String messageId, String userId) {
    showModalBottomSheet(
        context: context,
        builder: (context) {
          return SafeArea(
              child: Wrap(children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title:
                  const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                confirmDeleteMessage(context, messageId, userId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ]));
        });
  }

  void confirmDeleteMessage(
      BuildContext context, String messageId, String userId) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Delete message'),
              content:
                  const Text('Are you sure you want to delete this message?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      ChatService().deleteMessage(widget.otherUserId, messageId);
                      Navigator.pop(context);
                    },
                    child: const Text('Delete',
                        style: TextStyle(color: Colors.red))),
              ],
            ));
  }

  //show options
  void showOptions(BuildContext context, String messageId, String userId) {
    showModalBottomSheet(
        context: context,
        builder: (context) {
          return SafeArea(
              child: Wrap(children: [
            ListTile(
              leading: const Icon(Icons.flag),
              title: const Text('Report'),
              onTap: () {
                Navigator.pop(context);
                reportMessage(context, messageId, userId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Block'),
              onTap: () {
                Navigator.pop(context);
                blockUser(context, userId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ]));
        });
  }

  void reportMessage(BuildContext context, String messageId, String userId) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Report message'),
              content:
                  const Text('Are you sure you want to report this message?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      ChatService().reportUser(messageId, userId);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Message reported!')));
                    },
                    child: const Text('Confirm')),
              ],
            ));
  }

  void blockUser(BuildContext context, String userId) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Block user'),
              content: const Text('Are you sure you want to block this user?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      ChatService().blockUser(userId);
                      Navigator.pop(context);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('User blocked!')));
                    },
                    child: const Text('Confirm')),
              ],
            ));
  }

  void showEmojiPicker(BuildContext context) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        widget.isCurrentUser ? position.dx - 100 : position.dx,
        position.dy - 50,
        widget.isCurrentUser ? position.dx + size.width : position.dx + 250,
        position.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: ChatBubble.quickEmojis.map((emoji) {
              return GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  widget.onReact?.call(emoji);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final DateTime date = timestamp.toDate();
    final DateTime now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;

    final reactionWidgets = _buildReactions(isDarkMode);

    final bubbleContent = Column(
      crossAxisAlignment: widget.isCurrentUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        // Reply citation
        if (widget.replyToMessage != null && widget.replyToMessage!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.grey.shade700.withOpacity(0.5)
                  : Colors.grey.shade300.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: const Border(
                left: BorderSide(
                  color: Colors.orange,
                  width: 4,
                ),
              ),
            ),
            child: Text(
              widget.replyToMessage!.length > 60
                  ? '${widget.replyToMessage!.substring(0, 60)}...'
                  : widget.replyToMessage!,
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

        // Message bubble
        GestureDetector(
          onLongPress: () {
            if (!widget.isCurrentUser) {
              showOptions(context, widget.messageId, widget.userId);
            } else {
              showDeleteOptions(context, widget.messageId, widget.userId);
            }
          },
          onDoubleTap: () {
            if (widget.onReact != null) {
              showEmojiPicker(context);
            }
          },
          child: Container(
            decoration: BoxDecoration(
                color: widget.isCurrentUser
                    ? Colors.orange
                    : (isDarkMode
                        ? Colors.grey.shade800
                        : Colors.grey.shade200),
                borderRadius: BorderRadius.circular(18)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              alignment: WrapAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 2, top: 2),
                  child: widget.messageType == 'post_share'
                    ? _buildPostShare(isDarkMode)
                    : Text(
                        widget.message,
                        style: TextStyle(
                            color: widget.isCurrentUser
                                ? Colors.white
                                : (isDarkMode ? Colors.white : Colors.black)),
                      ),
                ),
                if (widget.timestamp != null)
                  Text(
                    _formatTimestamp(widget.timestamp!) + (widget.showSeen ? ' • seen' : ''),
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.isCurrentUser
                          ? Colors.white70
                          : (isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Reactions row
        if (reactionWidgets.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
              spacing: 4,
              children: reactionWidgets,
            ),
          ),
      ],
    );

    // Custom swipe-to-reply with capped offset
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(
        children: [
          // Reply icon behind the message
          if (_dragOffset > 10)
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: (_dragOffset / _triggerThreshold).clamp(0.0, 1.0),
                  child: Icon(
                    Icons.reply,
                    color:
                        _replyTriggered ? Colors.orange : Colors.grey.shade500,
                    size: 24,
                  ),
                ),
              ),
            ),
          // Message content slides right
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: Container(
              alignment: widget.isCurrentUser
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 25),
              child: bubbleContent,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildReactions(bool isDarkMode) {
    if (widget.reactions == null || widget.reactions!.isEmpty) return [];

    final Map<String, int> emojiCounts = {};
    final Map<String, bool> userReacted = {};

    for (final entry in widget.reactions!.entries) {
      emojiCounts[entry.value] = (emojiCounts[entry.value] ?? 0) + 1;
      if (entry.key == widget.currentUserId) {
        userReacted[entry.value] = true;
      }
    }

    return emojiCounts.entries.map((entry) {
      final isUserReaction = userReacted[entry.key] == true;
      return GestureDetector(
        onTap: () => widget.onReact?.call(entry.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isUserReaction
                ? Colors.orange.withValues(alpha: 0.3)
                : (isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
            border: isUserReaction
                ? Border.all(color: Colors.orange, width: 1)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(entry.key, style: const TextStyle(fontSize: 14)),
              if (entry.value > 1) ...[
                const SizedBox(width: 2),
                Text(
                  '${entry.value}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildPostShare(bool isDarkMode) {
    if (widget.sharedPostId == null) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('posts').doc(widget.sharedPostId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Text("Post unavailable", style: TextStyle(fontStyle: FontStyle.italic));
        }

        final post = Post.fromFirestore(snapshot.data!);
        
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => PostDetailPage(post: post)),
            );
          },
          child: Container(
            width: 200,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey.shade900 : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade400, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      post.authorUsername,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  post.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("View post", style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                    Icon(Icons.arrow_forward_ios, size: 10, color: Colors.blue),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
