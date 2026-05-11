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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatelessWidget {
  final String userId;
  final String username;

  const ProfilePage({
    super.key,
    required this.userId,
    required this.username,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService().getCurrentUser()!.uid;
    final isOwnProfile = currentUserId == userId;
    final userService = UserService();
    final postService = PostService();

    return Scaffold(
      appBar: AppBar(
        title: UsernameDisplay(
          userId: userId,
          username: username,
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 20),
          iconSize: 20,
        ),
        foregroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          if (isOwnProfile)
            StreamBuilder<List<String>>(
              stream: userService.getFollowRequestsStream(currentUserId),
              builder: (context, snapshot) {
                final requests = snapshot.data ?? [];
                return IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FollowRequestsPage(),
                      ),
                    );
                  },
                  icon: Badge(
                    isLabelVisible: requests.isNotEmpty,
                    child: const Icon(Icons.notifications_outlined),
                  ),
                );
              },
            ),
          if (!isOwnProfile)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'block') {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Block User'),
                      content: Text('Are you sure you want to block @$username?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final chatService = ChatService();
                            await chatService.blockUser(userId);
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('User blocked!')),
                              );
                              // Pop the profile page to go back
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
      body: StreamBuilder<DocumentSnapshot>(
        stream: userService.getUserStream(userId),
        builder: (context, userSnapshot) {
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            return const Center(child: Text('User not found.'));
          }

          final userData = userSnapshot.data!.data() as Map<String, dynamic>;
          final followers =
              List<String>.from(userData['followers'] ?? []);
          final following =
              List<String>.from(userData['following'] ?? []);
          final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
          
          final isPublic = userData['public_account'] ?? false;
          final isFollowing = followers.contains(currentUserId);

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 24),

                // Profile picture
                CircleAvatar(
                  radius: 45,
                  backgroundColor: Colors.orange.withValues(alpha: 0.2),
                  backgroundImage:
                      photoUrl != null && isOwnProfile
                          ? NetworkImage(photoUrl)
                          : null,
                  child: (photoUrl == null || !isOwnProfile)
                      ? Text(
                          username.isNotEmpty
                              ? username[0].toUpperCase()
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
                  userId: userId,
                  username: username,
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
                              userId: userId,
                              title: 'Followers',
                              isFollowers: true,
                            ),
                          ),
                        );
                      },
                      child: Column(
                        children: [
                          Text(
                            '${followers.length}',
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
                              userId: userId,
                              title: 'Following',
                              isFollowers: false,
                            ),
                          ),
                        );
                      },
                      child: Column(
                        children: [
                          Text(
                            '${following.length}',
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
                  StreamBuilder<bool>(
                    stream: userService.hasRequestedFollow(userId),
                    builder: (context, requestSnapshot) {
                      final hasRequested = requestSnapshot.data ?? false;

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
                                onPressed: () {
                                  if (isFollowing) {
                                    userService.unfollowUser(userId);
                                  } else if (hasRequested) {
                                    userService.cancelFollowRequest(userId);
                                  } else {
                                    if (isPublic) {
                                      userService.followUser(userId);
                                    } else {
                                      userService.requestFollow(userId);
                                    }
                                  }
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
                                        receiverUsername: username,
                                        receiverID: userId,
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
                if (!isOwnProfile && !isPublic && !isFollowing)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
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
                else
                  StreamBuilder(
                  stream: postService.getUserPostsStream(userId),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Error loading posts.'),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final posts = snapshot.data!.docs
                        .map((doc) => Post.fromFirestore(doc))
                        .toList();
                    
                    posts.sort((a, b) => b.timestamp.compareTo(a.timestamp));

                    if (posts.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'No posts yet.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
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
                              ? () => postService.deletePost(posts[index].id)
                              : null,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
