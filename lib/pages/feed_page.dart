import 'package:asiimov/components/my_drawer.dart';
import 'package:asiimov/components/post_card.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/pages/create_post_page.dart';
import 'package:asiimov/pages/post_detail_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FeedPage extends StatelessWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final postService = PostService();
    final userService = UserService();
    final currentUserId = AuthService().getCurrentUser()!.uid;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'A S I I M O V',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      drawer: const MyDrawer(),
      body: StreamBuilder<DocumentSnapshot>(
        stream: userService.getUserStream(currentUserId),
        builder: (context, userSnapshot) {
          if (userSnapshot.hasError) {
            return const Center(child: Text('Error loading user data.'));
          }
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
          final following = List<String>.from(userData?['following'] ?? []);
          
          // Add current user to the list so they see their own posts too
          final allowedUserIds = [...following, currentUserId];

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(currentUserId)
                .collection('blockedUsers')
                .snapshots(),
            builder: (context, blockedSnapshot) {
              final blockedUserIds = blockedSnapshot.data?.docs.map((doc) => doc.id).toList() ?? [];

              return StreamBuilder(
                stream: postService.getPostsStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('Error loading posts.'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // Filter posts to only include those from followed users or self, and NOT blocked users
                  final posts = snapshot.data!.docs
                      .map((doc) => Post.fromFirestore(doc))
                      .where((post) => allowedUserIds.contains(post.authorID) && !blockedUserIds.contains(post.authorID))
                  .toList();

              if (posts.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.article_outlined,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        'No posts yet.\nFollow someone or be the first to post!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              }

          return RefreshIndicator(
            onRefresh: () async {
              // StreamBuilder auto-refreshes, this is for UX feel
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: posts.length,
              itemBuilder: (context, index) {
                final post = posts[index];
                return PostCard(
                  post: post,
                  currentUserId: currentUserId,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PostDetailPage(post: post),
                      ),
                    );
                  },
                  onDelete: () => postService.deletePost(post.id),
                );
              },
            ),
          );
        },
      );
        },
      );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreatePostPage(),
            ),
          );
        },
        backgroundColor: Colors.orange,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }
}
