import 'package:asiimov/components/profile_post_card.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/pages/chat_page.dart';
import 'package:asiimov/pages/follow_list_page.dart';
import 'package:asiimov/pages/follow_requests_page.dart';
import 'package:asiimov/pages/post_detail_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatefulWidget {
  final String userId;
  final String username;

  const ProfilePage({
    super.key,
    required this.userId,
    required this.username,
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

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  Future<void> _refreshData() async {
    try {
      final userDoc = await userService.getUserFuture(widget.userId);
      if (userDoc.exists) {
        userData = userDoc.data() as Map<String, dynamic>;
        final followers = List<String>.from(userData!['followers'] ?? []);
        isFollowing = followers.contains(currentUserId);
        
        final isPublic = userData!['public_account'] ?? false;
        final isOwnProfile = currentUserId == widget.userId;

        if (isOwnProfile || isPublic || isFollowing) {
          final postsSnapshot = await postService.getUserPostsFuture(widget.userId);
          posts = postsSnapshot.docs.map((doc) => Post.fromFirestore(doc)).toList();
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

  @override
  Widget build(BuildContext context) {
    final isOwnProfile = currentUserId == widget.userId;

    return Scaffold(
      appBar: AppBar(
        title: UsernameDisplay(
          userId: widget.userId,
          username: widget.username,
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 20),
          iconSize: 20,
        ),
        foregroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          if (isOwnProfile)
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
          if (!isOwnProfile)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'block') {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Block User'),
                      content: Text('Are you sure you want to block @${widget.username}?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final chatService = ChatService();
                            await chatService.blockUser(widget.userId);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('User blocked!')),
                              );
                              Navigator.pop(context);
                            }
                          },
                          child: const Text('Block', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(Icons.block, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text('Block User', style: TextStyle(color: Colors.red)),
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
            ? const Center(child: CircularProgressIndicator())
            : userData == null
                ? const Center(child: Text('User not found.'))
                : SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),

                        // Profile picture
                        CircleAvatar(
                          radius: 45,
                          backgroundColor: Colors.orange.withValues(alpha: 0.2),
                          backgroundImage:
                              FirebaseAuth.instance.currentUser?.photoURL != null && isOwnProfile
                                  ? NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!)
                                  : null,
                          child: (FirebaseAuth.instance.currentUser?.photoURL == null || !isOwnProfile)
                              ? Text(
                                  widget.username.isNotEmpty
                                      ? widget.username[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange,
                                  ),
                                )
                              : null,
                        ),

                        const SizedBox(height: 12),

                        // Username
                        UsernameDisplay(
                          userId: widget.userId,
                          username: widget.username,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          iconSize: 20,
                        ),

                        const SizedBox(height: 16),

                        // Followers / Following counts
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => FollowListPage(
                                      userId: widget.userId,
                                      title: 'Followers',
                                      isFollowers: true,
                                    ),
                                  ),
                                );
                              },
                              child: Column(
                                children: [
                                  Text(
                                    '${(userData!['followers'] as List? ?? []).length}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'followers',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 30,
                              color: Theme.of(context).colorScheme.secondary,
                              margin: const EdgeInsets.symmetric(horizontal: 24),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => FollowListPage(
                                      userId: widget.userId,
                                      title: 'Following',
                                      isFollowers: false,
                                    ),
                                  ),
                                );
                              },
                              child: Column(
                                children: [
                                  Text(
                                    '${(userData!['following'] as List? ?? []).length}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'following',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Follow/Unfollow button (only on other profiles)
                        if (!isOwnProfile)
                          Builder(
                            builder: (context) {
                              final isPublic = userData!['public_account'] ?? false;

                              String buttonText = 'Follow';
                              Color buttonColor = Colors.orange;
                              Color textColor = Colors.white;

                              if (isFollowing) {
                                buttonText = 'Unfollow';
                                buttonColor = Theme.of(context).colorScheme.secondary;
                                textColor = Theme.of(context).colorScheme.inversePrimary;
                              } else if (hasRequested) {
                                buttonText = 'Requested';
                                buttonColor = Theme.of(context).colorScheme.secondary;
                                textColor = Theme.of(context).colorScheme.inversePrimary;
                              }

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 40),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () async {
                                          if (isFollowing) {
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
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                        child: Text(
                                          buttonText,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.secondary,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: IconButton(
                                        onPressed: () {
                                          if (!isPublic && !isFollowing) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('This account is private. Follow them to send messages.')),
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
                                        icon: const Icon(Icons.mail_outline),
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                        const SizedBox(height: 20),

                        // Divider
                        Divider(
                          color: Theme.of(context).colorScheme.secondary,
                          height: 1,
                        ),

                        // Posts
                        if (!isOwnProfile && !(userData!['public_account'] ?? false) && !isFollowing)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Private Account',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Follow this account to see their posts and send them messages.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
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
                            itemCount: posts.length,
                            itemBuilder: (context, index) {
                              return ProfilePostCard(
                                post: posts[index],
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          PostDetailPage(post: posts[index]),
                                    ),
                                  );
                                },
                                onDelete: isOwnProfile
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
