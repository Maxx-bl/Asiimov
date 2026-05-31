import 'dart:io';
import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/components/profile_post_card.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/models/post.dart';
import 'package:image_picker/image_picker.dart';
import 'package:asiimov/pages/chat_page.dart';
import 'package:asiimov/pages/follow_list_page.dart';
import 'package:asiimov/pages/follow_requests_page.dart';
import 'package:asiimov/pages/post_detail_page.dart';
import 'package:asiimov/pages/settings_page.dart';
import 'package:asiimov/pages/admin_dashboard_page.dart';
import 'package:asiimov/components/logout_confirmation_dialog.dart';
import 'package:asiimov/components/report_reason_dialog.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/image/image_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/widgets/safe_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class ProfilePage extends StatefulWidget {
  final String userId;
  final String username;
  final bool isAdminView;

  const ProfilePage({
    super.key,
    required this.userId,
    required this.username,
    this.isAdminView = false,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final userService = UserService();
  final postService = PostService();
  final currentUserId = AuthService().getCurrentUser()!.uid;

  Map<String, dynamic>? userData;
  List<Post> posts = [];
  bool isFollowing = false;
  bool hasRequested = false;
  int requestCount = 0;
  bool isLoading = true;
  bool isBlockedByMe = false;
  bool hasBlockedMe = false;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    try {
      final isOwnProfile = currentUserId == widget.userId;

      if (!isOwnProfile) {
        final blockedByMeDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('blockedUsers')
            .doc(widget.userId)
            .get();
        isBlockedByMe = blockedByMeDoc.exists;

        final blockedMeDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('blockedUsers')
            .doc(currentUserId)
            .get();
        hasBlockedMe = blockedMeDoc.exists;
      } else {
        isBlockedByMe = false;
        hasBlockedMe = false;
      }

      if (hasBlockedMe) {
        posts = [];
        isFollowing = false;
        hasRequested = false;
        userData = {}; // Empty map to bypass the "User not found" check
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        return;
      }

      final userDoc = await userService.getUserFuture(widget.userId);
      if (userDoc.exists) {
        userData = userDoc.data() as Map<String, dynamic>;
        final followers = List<String>.from(userData!['followers'] ?? []);
        isFollowing = followers.contains(currentUserId);
        final isPublic = userData!['public_account'] ?? false;
        final isSuspended = userData!['isSuspended'] == true;
        
        if (!isSuspended && (isOwnProfile || isPublic || isFollowing || widget.isAdminView)) {
          final postsSnapshot = await postService.getUserPostsFuture(widget.userId);
          posts = postsSnapshot.docs
              .map((doc) => Post.fromFirestore(doc))
              .where((post) {
                if (post.isCloseFriendsOnly) {
                  return post.authorID == currentUserId || post.visibleTo.contains(currentUserId);
                }
                return true;
              })
              .toList();
          posts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        } else {
          posts = [];
        }

        if (isOwnProfile) {
          final requests = await userService.getFollowRequestsFuture(currentUserId);
          requestCount = requests.length;
        } else {
          hasRequested = await userService.hasRequestedFollowFuture(widget.userId);
        }
      }
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // Update only one post in the list (saves reads)
  Future<void> _updateSinglePost(String postId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
      if (doc.exists && mounted) {
        final newPost = Post.fromFirestore(doc);
        setState(() {
          final index = posts.indexWhere((p) => p.id == postId);
          if (index != -1) {
            posts[index] = newPost;
          }
        });
      }
    } catch (e) {
      debugPrint("Error updating single post: $e");
    }
  }

  Future<void> _changeProfilePicture() async {
    final hasCurrentPicture = userData != null && 
        userData!['profilePictureUrl'] != null && 
        userData!['profilePictureUrl'].toString().isNotEmpty;

    final action = await ImageService.showImageSourceSheet(context, showDeleteOption: hasCurrentPicture);
    if (action == null) return;

    final imageService = ImageService();

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: CircularProgressIndicator(color: Theme.of(context).primaryColor),
        ),
      );
    }

    if (action == 'delete') {
      final success = await imageService.deleteProfilePicture();
      // Pop loading dialog
      if (mounted) Navigator.pop(context);

      if (success) {
        imageService.invalidateCache(currentUserId);
        await _refreshData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('profile_picture_deleted'.tr())),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('failed_to_delete_profile_pictu'.tr())),
          );
        }
      }
      return;
    }

    final source = action == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final pickedFile = await imageService.pickImage(source);
    if (pickedFile == null) {
      if (mounted) Navigator.pop(context); // Pop loading if image picker cancelled
      return;
    }

    try {
      final url = await imageService.uploadProfilePicture(pickedFile);

      // Pop loading dialog
      if (mounted) Navigator.pop(context);

      if (url != null) {
        // Invalidate cache and refresh
        imageService.invalidateCache(currentUserId);
        await _refreshData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('profile_picture_updated'.tr())),
          );
        }
      }
    } catch (e) {
      // Pop loading dialog
      if (mounted) Navigator.pop(context);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile picture: $e')),
        );
      }
    }
  }

  Future<void> _editBio(String currentBio) async {
    final controller = TextEditingController(text: currentBio);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('edit_bio'.tr()),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(
                    controller: controller,
                    maxLength: 100,
                    maxLines: 4,
                    minLines: 2,
                    textInputAction: TextInputAction.newline,
                    onChanged: (value) {
                      // Allow only single newlines
                      final filtered = value.replaceAll(RegExp(r'\n{2,}'), '\n');
                      if (filtered != value) {
                        controller.value = controller.value.copyWith(
                          text: filtered,
                          selection: TextSelection.collapsed(offset: filtered.length),
                        );
                      }
                      setDialogState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'bio_hint'.tr(),
                      border: const OutlineInputBorder(),
                      counterText: '${controller.text.length}/100',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('cancel'.tr()),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: Text('save'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      final filtered = result.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
      await userService.updateBio(filtered);
      await _refreshData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwnProfile = currentUserId == widget.userId;

    return Scaffold(
      appBar: AppBar(
        title: UsernameDisplay(
          userId: widget.userId,
          username: widget.username,
          style: TextStyle(color: Theme.of(context).colorScheme.inversePrimary, fontSize: 18, fontWeight: FontWeight.w700),
          iconSize: 18,
        ),
        foregroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (isOwnProfile) ...[
            IconButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FollowRequestsPage(),
                  ),
                );
                _refreshData();
              },
              icon: Badge(
                isLabelVisible: requestCount > 0,
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) async {
                if (value == 'settings') {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsPage(),
                    ),
                  );
                } else if (value == 'admin') {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const AdminDashboardPage(),
                    ),
                  );
                } else if (value == 'logout') {
                  confirmAndSignOut(context);
                }
              },
              itemBuilder: (BuildContext context) {
                final isAdmin = userData?['isAdmin'] == true;
                return [
                  PopupMenuItem<String>(
                    value: 'settings',
                    child: Row(
                      children: [
                        const Icon(Icons.settings, size: 20),
                        const SizedBox(width: 8),
                        Text('settings'.tr()),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    PopupMenuItem<String>(
                      value: 'admin',
                      child: Row(
                        children: [
                          const Icon(Icons.admin_panel_settings, color: Colors.redAccent, size: 20),
                          const SizedBox(width: 8),
                          Text('drawer_admin'.tr(), style: const TextStyle(color: Colors.redAccent)),
                        ],
                      ),
                    ),
                  PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        const Icon(Icons.logout, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Text('drawer_logout'.tr(), style: const TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ];
              },
            ),
          ],
          if (!isOwnProfile && !hasBlockedMe)
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'block') {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('block_user'.tr()),
                      content: Text('Are you sure you want to block @${widget.username}?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('cancel'.tr()),
                        ),
                        TextButton(
                          onPressed: () async {
                            final chatService = ChatService();
                            await chatService.blockUser(widget.userId);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('user_blocked'.tr())),
                              );
                              _refreshData();
                            }
                          },
                          child: Text('block_action'.tr(), style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                } else if (value == 'unblock') {
                  final chatService = ChatService();
                  await chatService.unblockUser(widget.userId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('user_unblocked_1'.tr())),
                    );
                    _refreshData();
                  }
                } else if (value == 'report') {
                  final reason = await ReportReasonDialog.show(
                    context,
                    title: 'report_user'.tr(),
                  );
                  if (reason != null && reason.isNotEmpty && context.mounted) {
                    final currentUsername =
                        AuthService().getCurrentUser()?.displayName ?? 'Anonymous';
                    await userService.reportUserProfile(
                      reportedUserId: widget.userId,
                      reportedUsername: widget.username,
                      reason: reason,
                      reporterUsername: currentUsername,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('user_reported'.tr())),
                      );
                    }
                  }
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                if (isBlockedByMe)
                  PopupMenuItem<String>(
                    value: 'unblock',
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Text('unblock_user'.tr(), style: const TextStyle(color: Colors.green)),
                      ],
                    ),
                  )
                else
                  PopupMenuItem<String>(
                    value: 'block',
                    child: Row(
                      children: [
                        const Icon(Icons.block, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Text('block_user'.tr(), style: const TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                PopupMenuItem<String>(
                  value: 'report',
                  child: Row(
                    children: [
                      const Icon(Icons.report_problem_outlined, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text('report_user'.tr(), style: const TextStyle(color: Colors.orange)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: isLoading
            ? Center(child: CircularProgressIndicator())
            : hasBlockedMe
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.redAccent.withValues(alpha: 0.08),
                              border: Border.all(color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.35), width: 0.5),
                            ),
                            child: const Icon(Icons.block, size: 36, color: Colors.redAccent),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'user_blocked_you'.tr(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.inversePrimary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'cannot_view_profile'.tr(),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  )
                : isBlockedByMe
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80, height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.redAccent.withValues(alpha: 0.08),
                                  border: Border.all(color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.35), width: 0.5),
                                ),
                                child: const Icon(Icons.block, size: 36, color: Colors.redAccent),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'you_blocked_user'.tr(),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'cannot_view_posts'.tr(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey, fontSize: 14),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  final chatService = ChatService();
                                  await chatService.unblockUser(widget.userId);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('unblock_user'.tr())),
                                    );
                                    _refreshData();
                                  }
                                },
                                icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                                label: Text('unblock'.tr(), style: const TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : userData == null
                        ? Center(child: Text('user_not_found'.tr()))
                        : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // Profile header card
                        Builder(builder: (context) {
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          final cardShadow = isDark
                              ? BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 2))
                              : BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2));
                          final canSeeFollowLists = isOwnProfile ||
                              (userData!['public_account'] ?? false) ||
                              isFollowing ||
                              widget.isAdminView;

                          return Container(
                            margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondary,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.30),
                                width: 0.5,
                              ),
                              boxShadow: [cardShadow],
                            ),
                            child: Column(
                              children: [
                                // Avatar + Bio — layout depends on visibility
                                Builder(builder: (context) {
                                  final bio = userData!['bio'] as String? ?? '';
                                  final isPublic = userData!['public_account'] ?? false;
                                  final canSeeBio = isOwnProfile || isPublic || isFollowing || widget.isAdminView;

                                  Widget avatarWidget(double radius) => Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: SweepGradient(
                                        colors: [
                                          Theme.of(context).primaryColor.withValues(alpha: 0.70),
                                          Theme.of(context).primaryColor.withValues(alpha: 0.20),
                                          Theme.of(context).primaryColor.withValues(alpha: 0.70),
                                        ],
                                      ),
                                    ),
                                    child: ProfileAvatar(
                                      userId: widget.userId,
                                      username: widget.username,
                                      radius: radius,
                                      showEditIcon: isOwnProfile,
                                      onTap: isOwnProfile
                                          ? () => _changeProfilePicture()
                                          : () {
                                              showDialog(
                                                context: context,
                                                builder: (context) => Dialog(
                                                  backgroundColor: Colors.transparent,
                                                  elevation: 0,
                                                  child: GestureDetector(
                                                    behavior: HitTestBehavior.opaque,
                                                    onTap: () => Navigator.pop(context),
                                                    child: FutureBuilder<String?>(
                                                      future: ImageService().getProfilePictureUrl(widget.userId),
                                                      builder: (context, snapshot) {
                                                        final url = snapshot.data;
                                                        final size = MediaQuery.of(context).size.width * 0.65;
                                                        if (url != null && url.isNotEmpty) {
                                                          return Center(
                                                            child: ClipRRect(
                                                              borderRadius: BorderRadius.circular(20),
                                                              child: SizedBox(
                                                                width: size,
                                                                height: size,
                                                                child: SafeNetworkImage(url: url, fit: BoxFit.cover),
                                                              ),
                                                            ),
                                                          );
                                                        } else {
                                                          return Center(
                                                            child: CircleAvatar(
                                                              radius: size / 2,
                                                              backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                                                              child: Text(
                                                                widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?',
                                                                style: TextStyle(
                                                                  fontSize: size * 0.4,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: Theme.of(context).primaryColor,
                                                                ),
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                    ),
                                  );

                                  if (canSeeBio) {
                                    // pfp left + bio right
                                    return Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        avatarWidget(44),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: bio.isNotEmpty
                                                    ? Text(
                                                        bio,
                                                        style: TextStyle(
                                                          fontSize: 14.5,
                                                          color: Theme.of(context).colorScheme.inversePrimary.withValues(alpha: 0.85),
                                                          height: 1.45,
                                                        ),
                                                      )
                                                    : isOwnProfile
                                                        ? Text(
                                                            'bio_placeholder'.tr(),
                                                            style: TextStyle(
                                                              fontSize: 14.5,
                                                              fontStyle: FontStyle.italic,
                                                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.40),
                                                            ),
                                                          )
                                                        : const SizedBox.shrink(),
                                              ),
                                              if (isOwnProfile)
                                                GestureDetector(
                                                  onTap: () => _editBio(bio),
                                                  child: Padding(
                                                    padding: const EdgeInsets.only(left: 6, top: 1),
                                                    child: Icon(
                                                      Icons.edit_outlined,
                                                      size: 15,
                                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.45),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  } else {
                                    // pfp centered, no bio (private account not followed)
                                    return Center(child: avatarWidget(52));
                                  }
                                }),

                                const SizedBox(height: 14),

                                // Username + suspended badge
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      widget.username,
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(context).colorScheme.inversePrimary,
                                      ),
                                    ),
                                    if (userData!['isSuspended'] == true) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.redAccent, width: 0.5),
                                        ),
                                        child: Text(
                                          'suspended_account_label'.tr(),
                                          style: const TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),

                                const SizedBox(height: 18),

                                // Followers / Following counts
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: canSeeFollowLists
                                          ? () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => FollowListPage(
                                                    userId: widget.userId,
                                                    title: 'followers'.tr(),
                                                    isFollowers: true,
                                                  ),
                                                ),
                                              );
                                            }
                                          : null,
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          children: [
                                            Text(
                                              '${(userData!['followers'] as List? ?? []).length}',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(context).colorScheme.inversePrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'followers'.tr(),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 32,
                                      margin: const EdgeInsets.symmetric(horizontal: 28),
                                      color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.40),
                                    ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: canSeeFollowLists
                                          ? () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => FollowListPage(
                                                    userId: widget.userId,
                                                    title: 'following'.tr(),
                                                    isFollowers: false,
                                                  ),
                                                ),
                                              );
                                            }
                                          : null,
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          children: [
                                            Text(
                                              '${(userData!['following'] as List? ?? []).length}',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(context).colorScheme.inversePrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'following'.tr(),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                // Follow/Message buttons (only on other profiles)
                                if (!isOwnProfile && userData!['isSuspended'] != true)
                                  Builder(
                                    builder: (context) {
                                      final isPublic = userData!['public_account'] ?? false;

                                      String buttonText = 'follow'.tr();
                                      Color buttonColor = Theme.of(context).primaryColor;
                                      Color textColor = Colors.white;
                                      BorderSide? buttonBorder;

                                      if (isFollowing) {
                                        buttonText = 'unfollow'.tr();
                                        buttonColor = Theme.of(context).colorScheme.secondary;
                                        textColor = Theme.of(context).colorScheme.inversePrimary;
                                        buttonBorder = BorderSide(
                                          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.40),
                                          width: 0.5,
                                        );
                                      } else if (hasRequested) {
                                        buttonText = 'requested'.tr();
                                        buttonColor = Theme.of(context).colorScheme.secondary;
                                        textColor = Theme.of(context).colorScheme.inversePrimary;
                                        buttonBorder = BorderSide(
                                          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.40),
                                          width: 0.5,
                                        );
                                      }

                                      return Padding(
                                        padding: const EdgeInsets.only(top: 16),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: ElevatedButton(
                                                onPressed: () async {
                                                  if (isFollowing) {
                                                    if (!isPublic) {
                                                      final confirm = await showDialog<bool>(
                                                        context: context,
                                                        builder: (context) => AlertDialog(
                                                          title: Text('unfollow_private_account'.tr()),
                                                          content: Text('Are you sure you want to unfollow @${widget.username}? They will have to accept your request again if you want to follow them later.'),
                                                          actions: [
                                                            TextButton(
                                                              onPressed: () => Navigator.pop(context, false),
                                                              child: Text('cancel'.tr()),
                                                            ),
                                                            TextButton(
                                                              onPressed: () => Navigator.pop(context, true),
                                                              child: Text('Unfollow', style: TextStyle(color: Colors.red)),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                      if (confirm != true) return;
                                                    }
                                                    await userService.unfollowUser(widget.userId);
                                                  } else if (hasRequested) {
                                                    await userService.cancelFollowRequest(widget.userId);
                                                  } else {
                                                    if (isPublic) {
                                                      await userService.followUser(widget.userId);
                                                    } else {
                                                      await userService.requestFollow(widget.userId);
                                                    }
                                                  }
                                                  _refreshData();
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: buttonColor,
                                                  foregroundColor: textColor,
                                                  elevation: 0,
                                                  shadowColor: Colors.transparent,
                                                  side: buttonBorder,
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                                ),
                                                child: Text(buttonText),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Container(
                                              height: 46,
                                              width: 46,
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).colorScheme.surface,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.40),
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: IconButton(
                                                onPressed: () {
                                                  if (!isPublic && !isFollowing) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(content: Text('this_account_is_private_follow'.tr())),
                                                    );
                                                    return;
                                                  }
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => ChatPage(
                                                        receiverUsername: widget.username,
                                                        receiverID: widget.userId,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                icon: const Icon(Icons.mail_outline_rounded, size: 20),
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          );
                        }),

                        // Posts section header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Posts',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ),

                        // Posts
                        if (userData!['isSuspended'] == true)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 80, height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.redAccent.withValues(alpha: 0.08),
                                    border: Border.all(color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.35), width: 0.5),
                                  ),
                                  child: const Icon(Icons.gavel_rounded, size: 36, color: Colors.redAccent),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'account_suspended'.tr(),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.inversePrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'This user has been suspended for violating our community guidelines.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (!isOwnProfile && !(userData!['public_account'] ?? false) && !isFollowing)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 80, height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Theme.of(context).colorScheme.secondary,
                                    border: Border.all(color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.35), width: 0.5),
                                  ),
                                  child: Icon(Icons.lock_outline_rounded, size: 36, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.55)),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'private_account'.tr(),
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.inversePrimary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Follow this account to see their posts and send them messages.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else if (posts.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              'No posts yet.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: posts.length,
                            itemBuilder: (context, index) {
                              return ProfilePostCard(
                                post: posts[index],
                                onTap: () async {
                                  final deleted = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => PostDetailPage(
                                        post: posts[index],
                                        docPath: 'posts/${posts[index].id}',
                                      ),
                                    ),
                                  );
                                  if (deleted == true) {
                                    _refreshData();
                                  } else {
                                    _updateSinglePost(posts[index].id);
                                  }
                                },
                                onDelete: (isOwnProfile || widget.isAdminView)
                                    ? () async {
                                        await postService.deletePost(posts[index].id);
                                        _refreshData();
                                      }
                                    : null,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
