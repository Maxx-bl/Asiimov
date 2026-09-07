import 'package:asiimov/components/report_reason_dialog.dart';
import 'package:asiimov/components/post_attachment_viewer.dart';
import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/components/share_sheet.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/components/voters_list_sheet.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/pages/post_detail_page.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:asiimov/utils/time_ago.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';

class PostCard extends StatelessWidget {
  final Post post;
  final String currentUserId;
  final String? docPath;
  final Post? parentPost;
  final String? parentDocPath;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onAction;
  final bool isAdminView;

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
    this.isAdminView = false,
  });

  String _timeAgo(DateTime dateTime) => formatTimeAgo(dateTime);

  @override
  Widget build(BuildContext context) {
    final postService = PostService();

    final score = post.score;
    final hasUpvoted = post.upvotes.contains(currentUserId);
    final hasDownvoted = post.downvotes.contains(currentUserId);

    Color scoreColor;
    if (score > 0) {
      scoreColor = Theme.of(context).primaryColor;
    } else if (score < 0) {
      scoreColor = Colors.blue.shade400;
    } else {
      scoreColor = Colors.grey;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardShadow = isDark
        ? BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2))
        : BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.30),
            width: 0.5,
          ),
          boxShadow: [cardShadow],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: username + time + 3-dot menu
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
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .inversePrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _timeAgo(post.timestamp.toDate()),
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.50),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (post.isCloseFriendsOnly) ...[
                          GestureDetector(
                            onTap: () {
                              if (post.authorID == currentUserId) {
                                showModalBottomSheet(
                                  context: context,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => VotersListSheet(
                                    userIds: post.visibleTo,
                                    title: 'visible_to_close_friends'.tr(),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('visible_to_close_friends'.tr()),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.shade400
                                    .withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.people_alt_rounded,
                                color: Colors.greenAccent.shade400,
                                size: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            size: 20,
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.45),
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
                                  title: Text('delete_post'.tr()),
                                  content: Text(
                                      'are_you_sure_you_want_to_delet_2'.tr()),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: Text('cancel'.tr()),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: Text('delete'.tr(),
                                          style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true && onDelete != null) {
                                onDelete!();
                              }
                            } else if (value == 'report') {
                              final reason = await ReportReasonDialog.show(
                                context,
                                title: 'report_post'.tr(),
                              );

                              if (reason != null) {
                                try {
                                  await postService.reportPost(
                                    postId: post.id,
                                    content: post.content,
                                    authorId: post.authorID,
                                    authorUsername: post.authorUsername,
                                    reason: reason,
                                    attachmentTypes: post.attachments != null
                                        ? post.attachments!
                                            .map((a) =>
                                                (a is Map && a['type'] != null)
                                                    ? a['type'].toString()
                                                    : 'media')
                                            .toList()
                                        : [],
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'post_successfully_reported'.tr()),
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
                          itemBuilder: (BuildContext context) =>
                              <PopupMenuEntry<String>>[
                            if (post.authorID == currentUserId || isAdminView)
                              PopupMenuItem<String>(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    const Icon(Icons.delete_outline_rounded,
                                        color: Colors.redAccent, size: 20),
                                    const SizedBox(width: 8),
                                    Text('delete'.tr(),
                                        style: const TextStyle(
                                            color: Colors.redAccent)),
                                  ],
                                ),
                              ),
                            PopupMenuItem<String>(
                              value: 'report',
                              child: Row(
                                children: [
                                  Icon(Icons.flag_outlined,
                                      color: Theme.of(context).primaryColor,
                                      size: 20),
                                  const SizedBox(width: 8),
                                  Text('report'.tr(),
                                      style: TextStyle(
                                          color:
                                              Theme.of(context).primaryColor)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Parent embed (Twitter-style quote)
                if (parentPost != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 5, bottom: 10),
                    child: GestureDetector(
                      onTap: () async {
                        if (parentDocPath != null) {
                          final deleted = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PostDetailPage(
                                post: parentPost!,
                                docPath: parentDocPath!,
                              ),
                            ),
                          );
                          if (deleted == true && onAction != null) {
                            onAction!();
                          }
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .tertiary
                                .withValues(alpha: 0.40),
                            width: 0.5,
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
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '· ${_timeAgo(parentPost!.timestamp.toDate())}',
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.5),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Linkify(
                              onOpen: (link) async {
                                final Uri url = Uri.parse(link.url);
                                final bool? shouldLeave =
                                    await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text('leaving_app'.tr()),
                                    content: Text(
                                        'This link will take you to an external website:\n\n${link.url}\n\nDo you want to continue?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text('cancel'.tr()),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text('continue_action'.tr(),
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .primaryColor)),
                                      ),
                                    ],
                                  ),
                                );

                                if (shouldLeave == true) {
                                  try {
                                    await launchUrl(url,
                                        mode: LaunchMode.externalApplication);
                                  } catch (e) {
                                    debugPrint(
                                        'Could not launch ${link.url}: $e');
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'could_not_open_the_link'
                                                    .tr())),
                                      );
                                    }
                                  }
                                }
                              },
                              text: parentPost!.content,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.3,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.7),
                              ),
                              linkStyle: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.7),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Content
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (post.content.isNotEmpty)
                        Linkify(
                          onOpen: (link) async {
                            final Uri url = Uri.parse(link.url);
                            final bool? shouldLeave = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text('leaving_app'.tr()),
                                content: Text(
                                    'This link will take you to an external website:\n\n${link.url}\n\nDo you want to continue?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: Text('cancel'.tr()),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text('continue_action'.tr(),
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .primaryColor)),
                                  ),
                                ],
                              ),
                            );

                            if (shouldLeave == true) {
                              try {
                                await launchUrl(url,
                                    mode: LaunchMode.externalApplication);
                              } catch (e) {
                                debugPrint('Could not launch ${link.url}: $e');
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'could_not_open_the_link'.tr())),
                                  );
                                }
                              }
                            }
                          },
                          text: post.content,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          linkStyle: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      if (post.attachments != null &&
                          post.attachments!.isNotEmpty)
                        PostAttachmentViewer(attachments: post.attachments!),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Action bar: votes + comments + share
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: Row(
                    children: [
                      // Vote pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .tertiary
                                .withValues(alpha: 0.35),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                                    title: 'upvotes'.tr(),
                                  ),
                                );
                              },
                              child: Icon(
                                Icons.arrow_upward_rounded,
                                size: 18,
                                color: hasUpvoted
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '$score',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: scoreColor,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 5),
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
                                    title: 'downvotes'.tr(),
                                  ),
                                );
                              },
                              child: Icon(
                                Icons.arrow_downward_rounded,
                                size: 18,
                                color: hasDownvoted
                                    ? Colors.blue.shade400
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 14),

                      // Comments
                      GestureDetector(
                        onTap: onTap,
                        child: Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.55),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${post.commentCount}',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.55),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 20),

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
                              title: 'shares'.tr(),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Icon(
                              Icons.send_rounded,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.55),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${post.shareCount}',
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.55),
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
        ),
      ),
    );
  }
}
