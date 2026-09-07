import 'package:asiimov/models/post.dart';
import 'package:asiimov/utils/time_ago.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

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

  String _timeAgo(DateTime dateTime) => formatTimeAgo(dateTime);

  @override
  Widget build(BuildContext context) {
    final upCount = post.upvotes.length;
    final downCount = post.downvotes.length;
    final total = upCount - downCount;

    Color totalColor;
    if (total > 0) {
      totalColor = Theme.of(context).primaryColor;
    } else if (total < 0) {
      totalColor = Colors.blue.shade400;
    } else {
      totalColor = Colors.grey;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardShadow = isDark
        ? BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 2))
        : BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2));

    return GestureDetector(
      onTap: onTap,
      onLongPress: () {
        if (onDelete != null) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('delete_post_1'.tr()),
              content: Text('are_you_sure_you_want_to_delet_2'.tr()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('cancel'.tr()),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onDelete!();
                  },
                  child: Text('Delete',
                      style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.30),
            width: 0.5,
          ),
          boxShadow: [cardShadow],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timestamp top-right + close friends badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (post.isCloseFriendsOnly)
                      Icon(Icons.people_alt_rounded,
                          size: 14, color: Colors.greenAccent.shade400)
                    else
                      const SizedBox.shrink(),
                    Text(
                      _timeAgo(post.timestamp.toDate()),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Content
                Text(
                  post.content,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Divider(
                    color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.30),
                    thickness: 0.5,
                    height: 0,
                  ),
                ),

                // Detailed vote stats
                Row(
                  children: [
                    // Upvotes
                    Icon(Icons.arrow_upward_rounded,
                        size: 15, color: Theme.of(context).primaryColor.withValues(alpha: 0.8)),
                    const SizedBox(width: 2),
                    Text(
                      '$upCount',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).primaryColor.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Downvotes
                    Icon(Icons.arrow_downward_rounded,
                        size: 15, color: Colors.blue.shade300),
                    const SizedBox(width: 2),
                    Text(
                      '$downCount',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade300,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Total
                    Text(
                      'total_label'.tr(),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65),
                      ),
                    ),
                    Text(
                      '$total',
                      style: TextStyle(
                        fontSize: 13,
                        color: totalColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(width: 20),

                    // Comments
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 15,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.commentCount}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.55),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
