import 'package:asiimov/models/post.dart';
import 'package:flutter/material.dart';

class ProfilePostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const ProfilePostCard({
    super.key,
    required this.post,
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
    final upCount = post.upvotes.length;
    final downCount = post.downvotes.length;
    final total = upCount - downCount;

    Color totalColor;
    if (total > 0) {
      totalColor = Colors.orange;
    } else if (total < 0) {
      totalColor = Colors.blue.shade400;
    } else {
      totalColor = Colors.grey;
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        if (onDelete != null) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete post'),
              content: const Text('Are you sure you want to delete this post?'),
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
            // Timestamp
            Row(
              children: [
                Text(
                  _timeAgo(post.timestamp.toDate()),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Content
            Text(
              post.content,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),

            const SizedBox(height: 10),

            // Detailed vote stats
            Row(
              children: [
                // Upvotes
                Icon(Icons.arrow_upward_rounded,
                    size: 16, color: Colors.orange.shade300),
                const SizedBox(width: 2),
                Text(
                  '$upCount',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange.shade300,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(width: 12),

                // Downvotes
                Icon(Icons.arrow_downward_rounded,
                    size: 16, color: Colors.blue.shade300),
                const SizedBox(width: 2),
                Text(
                  '$downCount',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade300,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(width: 12),

                // Total
                Text(
                  'Total: ',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Text(
                  '$total',
                  style: TextStyle(
                    fontSize: 13,
                    color: totalColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(width: 20),

                // Comments
                const Icon(Icons.chat_bubble_outline,
                    size: 15, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '${post.commentCount}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
