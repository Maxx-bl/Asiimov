import 'package:asiimov/components/post_attachment_viewer.dart';
import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/components/share_sheet.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/components/voters_list_sheet.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/pages/post_detail_page.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:flutter/material.dart';

class PostCard extends StatelessWidget {
  final Post post;
  final String currentUserId;
  final String? docPath;
  final Post? parentPost;
  final String? parentDocPath;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onAction;

  const PostCard({
    super.key,
    required this.post,
    required this.currentUserId,
    this.docPath,
    this.parentPost,
    this.parentDocPath,
    this.onTap,
    this.onDelete,
    this.onAction,
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

    final score = post.score;
    final hasUpvoted = post.upvotes.contains(currentUserId);
    final hasDownvoted = post.downvotes.contains(currentUserId);

    Color scoreColor;
    if (score > 0) {
      scoreColor = Colors.orange;
    } else if (score < 0) {
      scoreColor = Colors.blue.shade400;
    } else {
      scoreColor = Colors.grey;
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        if (post.authorID == currentUserId && onDelete != null) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete post'),
              content:
                  const Text('Are you sure you want to delete this post?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onDelete!();
                  },
                  child: const Text('Delete',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.secondary,
              width: 0.5,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: username + time
            Row(
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfilePage(
                          userId: post.authorID,
                          username: post.authorUsername,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      ProfileAvatar(
                        userId: post.authorID,
                        username: post.authorUsername,
                        radius: 18,
                      ),
                      const SizedBox(width: 10),
                      UsernameDisplay(
                        userId: post.authorID,
                        username: post.authorUsername,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '· ${_timeAgo(post.timestamp.toDate())}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Parent embed (Twitter-style quote)
            if (parentPost != null)
              Padding(
                padding: const EdgeInsets.only(left: 46, bottom: 10),
                child: GestureDetector(
                  onTap: () {
                    if (parentDocPath != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PostDetailPage(
                            post: parentPost!,
                            docPath: parentDocPath!,
                          ),
                        ),
                      );
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.secondary,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ProfileAvatar(
                              userId: parentPost!.authorID,
                              username: parentPost!.authorUsername,
                              radius: 10,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                parentPost!.authorUsername,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '· ${_timeAgo(parentPost!.timestamp.toDate())}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          parentPost!.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.3,
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Content
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (post.content.isNotEmpty)
                    Text(
                      post.content,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  if (post.attachments != null && post.attachments!.isNotEmpty)
                    PostAttachmentViewer(attachments: post.attachments!),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Action bar: votes + comments
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Row(
                children: [
                  // Upvote
                  GestureDetector(
                    onTap: () async {
                      final path = docPath ?? 'posts/${post.id}';
                      await postService.upvoteComment(path);
                      if (onAction != null) onAction!();
                    },
                    onLongPress: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (context) => VotersListSheet(
                          userIds: post.upvotes,
                          title: 'Upvotes',
                        ),
                      );
                    },
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      size: 20,
                      color: hasUpvoted ? Colors.orange : Colors.grey,
                    ),
                  ),

                  // Score
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '$score',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scoreColor,
                        fontSize: 14,
                      ),
                    ),
                  ),

                  // Downvote
                  GestureDetector(
                    onTap: () async {
                      final path = docPath ?? 'posts/${post.id}';
                      await postService.downvoteComment(path);
                      if (onAction != null) onAction!();
                    },
                    onLongPress: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (context) => VotersListSheet(
                          userIds: post.downvotes,
                          title: 'Downvotes',
                        ),
                      );
                    },
                    child: Icon(
                      Icons.arrow_downward_rounded,
                      size: 20,
                      color:
                          hasDownvoted ? Colors.blue.shade400 : Colors.grey,
                    ),
                  ),

                  const SizedBox(width: 24),

                  // Comments
                  GestureDetector(
                    onTap: onTap,
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            size: 18, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '${post.commentCount}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 24),

                  // Share
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) =>
                            ShareSheet(post: post, docPath: docPath),
                      );
                    },
                    onLongPress: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (context) => VotersListSheet(
                          userIds: post.sharedBy,
                          title: 'Shares',
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.send_rounded,
                            size: 18, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '${post.shareCount}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
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
