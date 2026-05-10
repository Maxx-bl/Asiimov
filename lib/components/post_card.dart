import 'package:asiimov/components/share_sheet.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/components/voters_list_sheet.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PostCard extends StatelessWidget {
  final Post post;
  final String currentUserId;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const PostCard({
    super.key,
    required this.post,
    required this.currentUserId,
    this.onTap,
    this.onDelete,
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

    return StreamBuilder<DocumentSnapshot>(
      stream: postService.getPostStream(post.id),
      builder: (context, snapshot) {
        // Use live data if available, otherwise fallback to the initial post object
        Post currentPost = post;
        if (snapshot.hasData && snapshot.data!.exists) {
          currentPost = Post.fromFirestore(snapshot.data!);
        }

        final score = currentPost.score;
        final hasUpvoted = currentPost.upvotes.contains(currentUserId);
        final hasDownvoted = currentPost.downvotes.contains(currentUserId);

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
            if (currentPost.authorID == currentUserId && onDelete != null) {
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
                              userId: currentPost.authorID,
                              username: currentPost.authorUsername,
                            ),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor:
                                Colors.orange.withValues(alpha: 0.2),
                            child: Text(
                              currentPost.authorUsername.isNotEmpty
                                  ? currentPost.authorUsername[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          UsernameDisplay(
                            userId: currentPost.authorID,
                            username: currentPost.authorUsername,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '· ${_timeAgo(currentPost.timestamp.toDate())}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Content
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: Text(
                    currentPost.content,
                    style: const TextStyle(fontSize: 15, height: 1.4),
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
                        onTap: () => postService.upvotePost(currentPost.id),
                        onLongPress: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (context) => VotersListSheet(
                              userIds: currentPost.upvotes,
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
                        onTap: () => postService.downvotePost(currentPost.id),
                        onLongPress: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (context) => VotersListSheet(
                              userIds: currentPost.downvotes,
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
                              '${currentPost.commentCount}',
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
                                ShareSheet(post: currentPost),
                          );
                        },
                        onLongPress: () {
                          showModalBottomSheet(
                            context: context,
                            backgroundColor: Colors.transparent,
                            builder: (context) => VotersListSheet(
                              userIds: currentPost.sharedBy,
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
                              '${currentPost.shareCount}',
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
      },
    );
  }
}
