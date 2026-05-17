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

class CommentTile extends StatelessWidget {
  final Comment comment;
  final String currentUserId;
  final String parentPath;
  final VoidCallback? onAction;

  const CommentTile({
    super.key,
    required this.comment,
    required this.currentUserId,
    required this.parentPath,
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
    final hasUpvoted = comment.upvotes.contains(currentUserId);
    final hasDownvoted = comment.downvotes.contains(currentUserId);
    
    Color scoreColor;
    if (comment.score > 0) {
      scoreColor = Colors.orange;
    } else if (comment.score < 0) {
      scoreColor = Colors.blue.shade400;
    } else {
      scoreColor = Colors.grey;
    }

    void showDeleteDialog(BuildContext context) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Comment'),
          content: const Text('Are you sure you want to delete this comment?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final commentPath = '$parentPath/comments/${comment.id}';
                await postService.deleteComment(commentPath);
                if (onAction != null) onAction!();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
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
      onLongPress: comment.authorID == currentUserId
          ? () => showDeleteDialog(context)
          : null,
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
                  const SizedBox(height: 4),
                  Text(
                    comment.content,
                    style: const TextStyle(fontSize: 14, height: 1.3),
                  ),
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
                          color: hasUpvoted ? Colors.orange : Colors.grey,
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
