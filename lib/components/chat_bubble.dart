import 'package:asiimov/components/report_reason_dialog.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/pages/post_detail_page.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/themes/theme_provider.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:asiimov/components/chat_attachment_viewer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

class ChatBubble extends StatefulWidget {
  final String message;
  final bool isCurrentUser;
  final String messageId;
  final String userId;
  final String? replyToMessageId;
  final String? replyToMessage;
  final String? replyToSenderID;
  final String? replyToSenderUsername;
  final String currentUserId;
  final String otherUserId;
  final String messageType;
  final String? sharedPostId;
  final Map<String, String>? reactions;
  final Map<String, String>? mentions;
  final Timestamp? timestamp;
  final bool isSeen;
  final bool showStatus;
  final bool isGroup;
  final bool isEdited;
  final bool isPinned;
  final bool isPending;
  final List<dynamic>? attachments;
  final Map<String, dynamic>? instantAttachment;
  final void Function(String emoji)? onReact;
  final void Function(String messageId, String content)? onEdit;
  final VoidCallback? onSwipeReply;
  final void Function(String messageId)? onReplyTap;

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
    this.replyToMessageId,
    this.replyToMessage,
    this.replyToSenderID,
    this.replyToSenderUsername,
    this.reactions,
    this.mentions,
    this.timestamp,
    this.isSeen = false,
    this.showStatus = false,
    this.isGroup = false,
    this.isEdited = false,
    this.isPinned = false,
    this.isPending = false,
    this.attachments,
    this.instantAttachment,
    this.onReact,
    this.onEdit,
    this.onSwipeReply,
    this.onReplyTap,
  });

  static const List<String> quickEmojis = ['❤️', '😂', '😮', '😢', '😡', '👍'];

  @override
  State<ChatBubble> createState() => ChatBubbleState();
}

class ChatBubbleState extends State<ChatBubble>
    with TickerProviderStateMixin {
  double _dragOffset = 0;
  bool _replyTriggered = false;
  static const double _maxDrag = 80;
  static const double _triggerThreshold = 60;

  late AnimationController _animController;
  late AnimationController _highlightController;
  late Animation<Color?> _highlightAnimation;

  // One recognizer per unique mentioned username
  final Map<String, TapGestureRecognizer> _mentionRecognizers = {};

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _highlightAnimation = ColorTween(
      begin: Colors.transparent,
      end: Colors.white.withValues(alpha: 0.15),
    ).animate(CurvedAnimation(
      parent: _highlightController,
      curve: Curves.easeInOut,
    ));

    _buildMentionRecognizers();
  }

  void _buildMentionRecognizers() {
    if (widget.mentions == null) return;
    for (final entry in widget.mentions!.entries) {
      _mentionRecognizers[entry.key] = TapGestureRecognizer()
        ..onTap = () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfilePage(
                userId: entry.value,
                username: entry.key,
              ),
            ),
          );
        };
    }
  }

  // Method to trigger the highlight flash
  void flash() {
    _highlightController.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _highlightController.reverse();
      });
    });
  }

  @override
  void dispose() {
    for (final r in _mentionRecognizers.values) {
      r.dispose();
    }
    _animController.dispose();
    _highlightController.dispose();
    super.dispose();
  }

  // Renders message text with tappable bold @mention spans
  Widget _buildMentionText(bool isDarkMode) {
    final textColor = widget.isCurrentUser
        ? (isDarkMode
            ? Colors.black
            : (Theme.of(context).primaryColor.computeLuminance() > 0.4
                ? Theme.of(context).colorScheme.inversePrimary
                : Colors.white))
        : (isDarkMode ? Colors.white : Theme.of(context).colorScheme.inversePrimary);

    final pattern = RegExp(r'@(\w+)', caseSensitive: false);
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in pattern.allMatches(widget.message)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: widget.message.substring(lastEnd, match.start),
          style: TextStyle(color: textColor),
        ));
      }

      final username = match.group(1)!.toLowerCase();
      spans.add(TextSpan(
        text: match.group(0)!,
        style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        recognizer: _mentionRecognizers[username],
      ));

      lastEnd = match.end;
    }

    if (lastEnd < widget.message.length) {
      spans.add(TextSpan(
        text: widget.message.substring(lastEnd),
        style: TextStyle(color: textColor),
      ));
    }

    return RichText(text: TextSpan(children: spans));
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
                  Text('delete'.tr(), style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                confirmDeleteMessage(context, messageId, userId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel),
              title: Text('cancel'.tr()),
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
              title: Text('delete_message'.tr()),
              content:
                  Text('are_you_sure_you_want_to_delet_1'.tr()),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('cancel'.tr())),
                TextButton(
                    onPressed: () {
                      ChatService().deleteMessage(widget.otherUserId, messageId, isGroup: widget.isGroup);
                      Navigator.pop(context);
                    },
                    child: Text('Delete',
                        style: TextStyle(color: Colors.red))),
              ],
            ));
  }

  // Unified Reaction & Options Menu (Instagram Style)
  void _showReactionMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // EMOJI MENU (Top Row)
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Predefined Emojis
                      ...ChatBubble.quickEmojis.map((emoji) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            widget.onReact?.call(emoji);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Text(emoji, style: const TextStyle(fontSize: 26)),
                          ),
                        );
                      }),

                      const SizedBox(width: 4),
                      Container(width: 1, height: 24, color: Colors.grey.withValues(alpha: 0.3)),
                      const SizedBox(width: 4),

                      // Full Picker (+) Button
                      IconButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _showFullEmojiPicker(context);
                        },
                        icon: Icon(Icons.add_circle_outline, 
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                          size: 26,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // ACTION MENU (Bottom Column)
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildActionTile(
                      context,
                      Icons.copy_rounded,
                      'copy'.tr(),
                      () {
                        Navigator.pop(context);
                        Clipboard.setData(ClipboardData(text: widget.message));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('copied_to_clipboard'.tr()),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
                    // Don't allow pinning messages with attachments or instant media (voice/camera)
                    if ((widget.attachments == null || widget.attachments!.isEmpty) && widget.instantAttachment == null) ...[
                    _buildActionTile(
                      context,
                      widget.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                      widget.isPinned ? 'unpin'.tr() : 'pin'.tr(),
                      () {
                        Navigator.pop(context);
                        ChatService().togglePinMessage(widget.otherUserId, widget.messageId, widget.isPinned, isGroup: widget.isGroup);
                      },
                      color: widget.isPinned ? Theme.of(context).primaryColor : null,
                    ),
                    ],
                    Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
                    if (!widget.isCurrentUser)
                      _buildActionTile(
                        context,
                        Icons.flag_rounded,
                        'report'.tr(),
                        () {
                          Navigator.pop(context);
                          reportMessage(context, widget.messageId, widget.userId);
                        },
                        color: Colors.redAccent,
                      )
                    else ...[
                      _buildActionTile(
                        context,
                        Icons.edit_rounded,
                        'edit'.tr(),
                        () {
                          Navigator.pop(context);
                          widget.onEdit?.call(widget.messageId, widget.message);
                        },
                      ),
                      Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
                      _buildActionTile(
                        context,
                        Icons.delete_rounded,
                        "Delete",
                        () {
                          Navigator.pop(context);
                          confirmDeleteMessage(context, widget.messageId, widget.userId);
                        },
                        color: Colors.redAccent,
                      ),
                    ]
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionTile(BuildContext context, IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 22, color: color ?? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)),
      title: Text(label, style: TextStyle(
        fontSize: 16, 
        fontWeight: FontWeight.w500,
        color: color ?? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
      )),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
    );
  }


  void _showFullEmojiPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.45,
          child: EmojiPicker(
            onEmojiSelected: (category, emoji) {
              Navigator.pop(context);
              widget.onReact?.call(emoji.emoji);
            },
            config: Config(
              height: 256,
              checkPlatformCompatibility: true,
              viewOrderConfig: const ViewOrderConfig(),
              emojiViewConfig: EmojiViewConfig(
                columns: 7,
                emojiSizeMax: 28 * (defaultTargetPlatform == TargetPlatform.iOS ? 1.30 : 1.0),
              ),
              skinToneConfig: const SkinToneConfig(),
              categoryViewConfig: const CategoryViewConfig(),
              bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
              searchViewConfig: const SearchViewConfig(),
            ),
          ),
        );
      },
    );
  }

  void reportMessage(BuildContext context, String messageId, String userId) async {
    final reason = await ReportReasonDialog.show(
      context,
      title: 'report_message'.tr(),
    );

    if (reason != null) {
      try {
        // Calculate chat room ID
        String chatRoomId;
        if (widget.isGroup) {
          chatRoomId = widget.otherUserId;
        } else {
          List<String> ids = [widget.currentUserId, widget.otherUserId];
          ids.sort();
          chatRoomId = ids.join('_');
        }

        // Fetch usernames
        final senderDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
        final reporterDoc = await FirebaseFirestore.instance.collection('users').doc(widget.currentUserId).get();

        final senderUsername = senderDoc.data()?['username'] as String? ?? 'Anonymous';
        final reporterUsername = reporterDoc.data()?['username'] as String? ?? 'Anonymous';

        await ChatService().reportUser(
          messageId,
          userId,
          widget.message,
          chatRoomId,
          senderUsername,
          reporterUsername,
          reason: reason,
          messageType: widget.messageType,
          sharedPostId: widget.sharedPostId,
          attachmentTypes: widget.attachments != null
              ? widget.attachments!.map((a) => (a is Map && a['type'] != null) ? a['type'].toString() : 'media').toList()
              : (widget.instantAttachment != null ? ['instant_photo'] : []),
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('message_successfully_reported'.tr())),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      }
    }
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
          GestureDetector(
            onTap: () {
              if (widget.replyToMessageId != null) {
                widget.onReplyTap?.call(widget.replyToMessageId!);
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? Colors.grey.shade700.withValues(alpha: 0.5)
                    : Colors.grey.shade300.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).primaryColor,
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
          ),

        // Attachments (images/videos/documents)
        if (widget.attachments != null && widget.attachments!.isNotEmpty)
          Builder(builder: (context) {
            List<dynamic> mediaAttachments = [];
            List<dynamic> docAttachments = [];
            for (var att in widget.attachments!) {
              if (att['type'] == 'image' || att['type'] == 'video') {
                mediaAttachments.add(att);
              } else {
                docAttachments.add(att);
              }
            }
            return Column(
              crossAxisAlignment: widget.isCurrentUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (mediaAttachments.isNotEmpty)
                  ChatMediaGrid(
                    attachments: mediaAttachments,
                    isDarkMode: isDarkMode,
                    onLongPress: () => _showReactionMenu(context),
                    onDoubleTap: () => widget.onReact?.call('❤️'),
                  ),
                if (docAttachments.isNotEmpty)
                  ...docAttachments.map((att) => ChatAttachmentViewer(
                        attachment: Map<String, dynamic>.from(att),
                        isDarkMode: isDarkMode,
                        onLongPress: () => _showReactionMenu(context),
                        onDoubleTap: () => widget.onReact?.call('❤️'),
                      )),
              ],
            );
          }),

        // Message bubble (only show if message text is not empty)
        if (widget.message.isNotEmpty)
        GestureDetector(
          onLongPress: () {
            _showReactionMenu(context);
          },
          onDoubleTap: () {
            widget.onReact?.call('❤️');
          },
          child: Container(
            decoration: BoxDecoration(
                color: widget.isCurrentUser
                    ? Theme.of(context).primaryColor
                    : Theme.of(context).colorScheme.secondary,
                borderRadius: BorderRadius.circular(18)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              alignment: WrapAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 2, top: 2),
                  child: widget.messageType == 'instant_attachment'
                      ? _buildInstantAttachment(isDarkMode)
                      : widget.messageType == 'post_share'
                          ? _buildPostShare(isDarkMode)
                          : (widget.mentions != null && widget.mentions!.isNotEmpty)
                              ? _buildMentionText(isDarkMode)
                              : Linkify(
                          onOpen: (link) async {
                            final Uri url = Uri.parse(link.url);
                            
                            final bool? shouldLeave = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('leaving_app'.tr()),
                                content: Text('This link will take you to an external website:\n\n${link.url}\n\nDo you want to continue?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: Text('cancel'.tr()),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: Text('continue_action'.tr(), style: TextStyle(color: Theme.of(context).primaryColor)),
                                  ),
                                ],
                              ),
                            );

                            if (shouldLeave == true) {
                              try {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              } catch (e) {
                                debugPrint('Could not launch ${link.url}: $e');
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('could_not_open_the_link'.tr())),
                                  );
                                }
                              }
                            }
                          },
                          text: widget.message,
                          style: TextStyle(
                              color: widget.isCurrentUser
                                  ? (isDarkMode
                                      ? Colors.black
                                      : (Theme.of(context).primaryColor.computeLuminance() > 0.4
                                          ? Theme.of(context).colorScheme.inversePrimary
                                          : Colors.white))
                                  : (isDarkMode ? Colors.white : Theme.of(context).colorScheme.inversePrimary)),
                          linkStyle: TextStyle(
                            color: widget.isCurrentUser
                                ? (isDarkMode
                                    ? Colors.black
                                    : (Theme.of(context).primaryColor.computeLuminance() > 0.4
                                        ? Theme.of(context).colorScheme.inversePrimary
                                        : Colors.white))
                                : (isDarkMode ? Colors.white : Theme.of(context).colorScheme.inversePrimary),
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none,
                          ),
                          options: const LinkifyOptions(humanize: false),
                        ),
                ),
                if (widget.timestamp != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isPinned) ...[
                        Icon(Icons.push_pin, size: 10, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 2),
                        Text(
                          'pinned_prefix'.tr(),
                          style: TextStyle(
                            fontSize: 10,
                            color: widget.isCurrentUser
                                ? (isDarkMode
                                    ? Colors.black54
                                    : (Theme.of(context).primaryColor.computeLuminance() > 0.4
                                        ? Theme.of(context).colorScheme.inversePrimary.withValues(alpha: 0.6)
                                        : Colors.white70))
                                : Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      Text(
                        (widget.isEdited ? 'edited_prefix'.tr() : '') +
                        _formatTimestamp(widget.timestamp!) +
                            (widget.showStatus
                                ? (widget.isPending
                                    ? ' • sending...'
                                    : (widget.isSeen ? 'status_seen'.tr() : 'status_sent'.tr()))
                                : ''),
                        style: TextStyle(
                          fontSize: 10,
                          color: widget.isCurrentUser
                              ? (isDarkMode
                                  ? Colors.black45
                                  : (Theme.of(context).primaryColor.computeLuminance() > 0.4
                                      ? Theme.of(context).colorScheme.inversePrimary.withValues(alpha: 0.5)
                                      : Colors.white70))
                              : (isDarkMode
                                  ? Colors.grey.shade400
                                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                        ),
                      ),
                    ],
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
          // Flash Overlay (Full width)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _highlightAnimation,
                builder: (context, child) => Container(
                  color: _highlightAnimation.value,
                ),
              ),
            ),
          ),

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
                        _replyTriggered ? Theme.of(context).primaryColor : Colors.grey.shade500,
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
              padding: EdgeInsets.only(
                top: 2,
                bottom: 2,
                left: widget.isCurrentUser ? 25 : (widget.isGroup ? 0 : 25),
                right: widget.isCurrentUser ? 25 : 25,
              ),
              child: Opacity(
                opacity: widget.isPending ? 0.45 : 1.0,
                child: bubbleContent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showReactionDetails(BuildContext context) {
    if (widget.reactions == null || widget.reactions!.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 15),
              Text(
                "Reactions",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: widget.reactions!.entries.map((entry) {
                    final userId = entry.key;
                    final emoji = entry.value;

                    return ListTile(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfilePage(
                              userId: userId,
                              username: "", // ProfilePage will fetch if empty or we can pass if we had it
                            ),
                          ),
                        );
                      },
                      title: UsernameDisplay(
                        userId: userId,
                        username: "", 
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 4),
                      trailing: Text(
                        emoji,
                        style: const TextStyle(fontSize: 22),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
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
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onReact?.call(entry.key),
        onLongPress: () {
          // Provide haptic feedback for better mobile experience
          HapticFeedback.lightImpact();
          _showReactionDetails(context);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isUserReaction
                ? Theme.of(context).primaryColor.withValues(alpha: 0.3)
                : (isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
            border: isUserReaction
                ? Border.all(color: Theme.of(context).primaryColor, width: 1)
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

    final String docPath = widget.sharedPostId!.contains('/') 
        ? widget.sharedPostId! 
        : 'posts/${widget.sharedPostId}';

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.doc(docPath).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Text('post_unavailable'.tr(), style: TextStyle(fontStyle: FontStyle.italic));
        }

        final post = Post.fromFirestore(snapshot.data!);
        
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => PostDetailPage(
                post: post,
                docPath: docPath,
              )),
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
                    Text('view_post'.tr(), style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
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

  Widget _buildInstantAttachment(bool isDarkMode) {
    if (widget.instantAttachment == null) return const SizedBox.shrink();
    final att = widget.instantAttachment!;
    final bool isVideo = att['type'] == 'video';
    final bool isAudio = att['type'] == 'audio';
    final String url = att['url'] ?? '';

    if (isAudio) {
      final int duration = att['duration'] ?? 0;
      return VoiceMessagePlayer(
        url: url,
        duration: duration,
        isCurrentUser: widget.isCurrentUser,
        isDarkMode: isDarkMode,
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MediaCarouselScreen(
              attachments: [att],
              initialIndex: 0,
            ),
          ),
        );
      },
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey.shade900 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).primaryColor, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 140,
                width: double.infinity,
                child: isVideo
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Center(child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor)),
                            errorWidget: (context, url, error) => const Icon(Icons.video_file, size: 40, color: Colors.grey),
                          ),
                          Center(
                            child: CircleAvatar(
                              backgroundColor: Colors.black54,
                              radius: 20,
                              child: Icon(Icons.play_arrow, color: Colors.white, size: 24),
                            ),
                          ),
                        ],
                      )
                    : CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Center(child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor)),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade900,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade600, size: 28),
                              const SizedBox(height: 4),
                              Text('media_deleted'.tr(), style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isVideo ? "Sent a video" : "Sent a photo",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class VoiceMessagePlayer extends StatefulWidget {
  final String url;
  final int duration;
  final bool isCurrentUser;
  final bool isDarkMode;

  const VoiceMessagePlayer({
    super.key,
    required this.url,
    required this.duration,
    required this.isCurrentUser,
    required this.isDarkMode,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _hasError = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _duration = Duration(seconds: widget.duration);
    _checkUrlValidity();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((newDuration) {
      if (mounted && newDuration > Duration.zero) {
        setState(() {
          _duration = newDuration;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((newPosition) {
      if (mounted) {
        setState(() {
          _position = newPosition;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _checkUrlValidity() async {
    if (widget.url.isEmpty) {
      if (mounted) setState(() => _hasError = true);
      return;
    }
    try {
      final response = await http.head(Uri.parse(widget.url));
      if (response.statusCode >= 400) {
        if (mounted) setState(() => _hasError = true);
      }
    } catch (_) {
      // Network error — don't mark as deleted, let play attempt handle it
    }
  }

  void _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      try {
        await _audioPlayer.play(UrlSource(widget.url));
      } catch (_) {
        if (mounted) setState(() => _hasError = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = widget.isCurrentUser
        ? Theme.of(context).primaryColor
        : Theme.of(context).colorScheme.secondary;

    if (widget.url.isEmpty || _hasError) {
      return Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_off_outlined, color: Colors.grey.shade500, size: 20),
            const SizedBox(width: 8),
            Text(
              'media_deleted'.tr(),
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      );
    }

    final Color fgColor = widget.isCurrentUser
        ? (widget.isDarkMode
            ? Colors.black
            : (Theme.of(context).primaryColor.computeLuminance() > 0.4
                ? Theme.of(context).colorScheme.inversePrimary
                : Colors.white))
        : (widget.isDarkMode ? Colors.white : Theme.of(context).colorScheme.inversePrimary);

    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _togglePlay,
            child: CircleAvatar(
              backgroundColor: fgColor.withValues(alpha: 0.2),
              radius: 18,
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: fgColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: _duration.inMilliseconds > 0
                      ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                      : 0.0,
                  backgroundColor: fgColor.withValues(alpha: 0.3),
                  valueColor: AlwaysStoppedAnimation<Color>(fgColor),
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_position.inMinutes}:${(_position.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 10, color: fgColor.withValues(alpha: 0.8)),
                    ),
                    Text(
                      '${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(fontSize: 10, color: fgColor.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
