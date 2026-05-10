import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/components/voters_list_sheet.dart';
import 'package:asiimov/models/comment.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:flutter/material.dart';

class CommentTile extends StatelessWidget {
  final Comment comment;
  final String currentUserId;
  final String postId;

  const CommentTile({
    super.key,
    required this.comment,
    required this.currentUserId,
    required this.postId,
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
              onPressed: () {
                postService.deleteComment(postId, comment.id);
                Navigator.pop(context);
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
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
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.orange.withValues(alpha: 0.2),
                child: Text(
                  comment.authorUsername.isNotEmpty
                      ? comment.authorUsername[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
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
                        onTap: () =>
                            postService.upvoteComment(postId, comment.id),
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
                        onTap: () =>
                            postService.downvoteComment(postId, comment.id),
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
