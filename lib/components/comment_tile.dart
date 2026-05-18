import 'package:asiimov/components/post_attachment_viewer.dart';
import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/components/share_sheet.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/components/voters_list_sheet.dart';
import 'package:asiimov/models/comment.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/pages/post_detail_page.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';

class CommentTile extends StatelessWidget {
  final Comment comment;
  final String currentUserId;
  final String parentPath;
  final VoidCallback? onAction;
  final bool isAdminView;

  const CommentTile({
    super.key,
    required this.comment,
    required this.currentUserId,
    required this.parentPath,
    this.onAction,
    this.isAdminView = false,
  });

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}min';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  @override
  Widget build(BuildContext context) {
    final postService = PostService();
    final hasUpvoted = comment.upvotes.contains(currentUserId);
    final hasDownvoted = comment.downvotes.contains(currentUserId);
    
    Color scoreColor;
    if (comment.score > 0) {
      scoreColor = Theme.of(context).primaryColor;
    } else if (comment.score < 0) {
      scoreColor = Colors.blue.shade400;
    } else {
      scoreColor = Colors.grey;
    }



    return GestureDetector(
      onTap: () async {
        final commentAsPost = Post(
          id: comment.id,
          authorID: comment.authorID,
          authorUsername: comment.authorUsername,
          content: comment.content,
          timestamp: comment.timestamp,
          upvotes: comment.upvotes,
          downvotes: comment.downvotes,
          commentCount: comment.commentCount,
          shareCount: comment.shareCount,
          sharedBy: comment.sharedBy,
        );
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailPage(
              post: commentAsPost,
              docPath: '$parentPath/comments/${comment.id}',
            ),
          ),
        );
        if (onAction != null) onAction!();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.secondary,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfilePage(
                      userId: comment.authorID,
                      username: comment.authorUsername,
                    ),
                  ),
                );
              },
              child: ProfileAvatar(
                userId: comment.authorID,
                username: comment.authorUsername,
                radius: 16,
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ProfilePage(
                                    userId: comment.authorID,
                                    username: comment.authorUsername,
                                  ),
                                ),
                              );
                            },
                            child: UsernameDisplay(
                              userId: comment.authorID,
                              username: comment.authorUsername,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· ${_timeAgo(comment.timestamp.toDate())}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          size: 18,
                          color: Colors.grey,
                        ),
                        color: Theme.of(context).colorScheme.secondary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onSelected: (value) async {
                          if (value == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Comment'),
                                content: const Text('Are you sure you want to delete this comment?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              final commentPath = '$parentPath/comments/${comment.id}';
                              await postService.deleteComment(commentPath);
                              if (onAction != null) onAction!();
                            }
                          } else if (value == 'report') {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Report Comment'),
                                content: const Text('Are you sure you want to report this comment?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: Text('Report', style: TextStyle(color: Theme.of(context).primaryColor)),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              try {
                                 await postService.reportComment(
                                   commentId: comment.id,
                                   commentPath: '$parentPath/comments/${comment.id}',
                                   content: comment.content,
                                   authorId: comment.authorID,
                                   authorUsername: comment.authorUsername,
                                   attachmentTypes: comment.attachments != null
                                       ? comment.attachments!.map((a) => (a is Map && a['type'] != null) ? a['type'].toString() : 'media').toList()
                                       : [],
                                 );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Comment successfully reported.'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: ${e.toString()}'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            }
                          }
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                          if (comment.authorID == currentUserId || isAdminView)
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                ],
                              ),
                            ),
                          PopupMenuItem<String>(
                            value: 'report',
                            child: Row(
                              children: [
                                Icon(Icons.flag_outlined, color: Theme.of(context).primaryColor, size: 18),
                                SizedBox(width: 8),
                                Text('Report', style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (comment.content.isNotEmpty)
                    Linkify(
                      onOpen: (link) async {
                        final Uri url = Uri.parse(link.url);
                        final bool? shouldLeave = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Leaving App'),
                            content: Text('This link will take you to an external website:\n\n${link.url}\n\nDo you want to continue?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text('Continue', style: TextStyle(color: Theme.of(context).primaryColor)),
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
                                const SnackBar(content: Text('Could not open the link.')),
                              );
                            }
                          }
                        }
                      },
                      text: comment.content,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      linkStyle: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  if (comment.attachments != null && comment.attachments!.isNotEmpty)
                    PostAttachmentViewer(attachments: comment.attachments!),
                  const SizedBox(height: 6),
                  // Votes
                   Row(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final commentPath = '$parentPath/comments/${comment.id}';
                          await postService.upvoteComment(commentPath);
                          if (onAction != null) onAction!();
                        },
                        onLongPress: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (context) => VotersListSheet(
                              userIds: comment.upvotes,
                              title: 'Upvotes',
                            ),
                          );
                        },
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          size: 16,
                          color: hasUpvoted ? Theme.of(context).primaryColor : Colors.grey,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '${comment.score}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: scoreColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final commentPath = '$parentPath/comments/${comment.id}';
                          await postService.downvoteComment(commentPath);
                          if (onAction != null) onAction!();
                        },
                        onLongPress: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (context) => VotersListSheet(
                              userIds: comment.downvotes,
                              title: 'Downvotes',
                            ),
                          );
                        },
                        child: Icon(
                          Icons.arrow_downward_rounded,
                          size: 16,
                          color:
                              hasDownvoted ? Colors.blue.shade400 : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Comments
                      GestureDetector(
                        onTap: () async {
                          final commentAsPost = Post(
                            id: comment.id,
                            authorID: comment.authorID,
                            authorUsername: comment.authorUsername,
                            content: comment.content,
                            timestamp: comment.timestamp,
                            upvotes: comment.upvotes,
                            downvotes: comment.downvotes,
                            commentCount: comment.commentCount,
                            shareCount: comment.shareCount,
                            sharedBy: comment.sharedBy,
                          );
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PostDetailPage(
                                post: commentAsPost,
                                docPath: '$parentPath/comments/${comment.id}',
                              ),
                            ),
                          );
                          if (onAction != null) onAction!();
                        },
                        child: Row(
                          children: [
                            const Icon(Icons.chat_bubble_outline,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              '${comment.commentCount}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Share
                      GestureDetector(
                        onTap: () {
                          final commentAsPost = Post(
                            id: comment.id,
                            authorID: comment.authorID,
                            authorUsername: comment.authorUsername,
                            content: comment.content,
                            timestamp: comment.timestamp,
                            upvotes: comment.upvotes,
                            downvotes: comment.downvotes,
                            commentCount: comment.commentCount,
                            shareCount: comment.shareCount,
                            sharedBy: comment.sharedBy,
                          );
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) => ShareSheet(
                              post: commentAsPost,
                              docPath: '$parentPath/comments/${comment.id}',
                            ),
                          );
                        },
                        onLongPress: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (context) => VotersListSheet(
                              userIds: comment.sharedBy,
                              title: 'Shares',
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            const Icon(Icons.send_rounded,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              '${comment.shareCount}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
