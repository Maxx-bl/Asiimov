import 'dart:async';

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

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final PostService postService = PostService();
  final UserService userService = UserService();
  final String currentUserId = AuthService().getCurrentUser()!.uid;

  final ScrollController _scrollController = ScrollController();
  List<Post> _posts = [];
  int _limit = 20;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  List<String> _blockedUserIds = [];
  List<String> _allowedUserIds = [];

  @override
  void initState() {
    super.initState();
    _initializeFeed();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _initializeFeed() async {
    try {
      // Get user data and blocked list
      final userDoc = await userService.getUserFuture(currentUserId);
      final userData = userDoc.data() as Map<String, dynamic>?;
      final following = List<String>.from(userData?['following'] ?? []);
      _allowedUserIds = [...following, currentUserId];

      final blockedSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('blockedUsers')
          .get();
      _blockedUserIds = blockedSnapshot.docs.map((doc) => doc.id).toList();

      await _fetchPosts();
    } catch (e) {
      debugPrint("Error initializing feed: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchPosts({bool refresh = false}) async {
    if (refresh) {
      _limit = 20;
      _hasMorePosts = true;
    }

    try {
      final snapshot = await postService.getPostsFuture(_limit);
      final fetchedPosts = snapshot.docs
          .map((doc) => Post.fromFirestore(doc))
          .where((post) =>
              (_allowedUserIds.contains(post.authorID) ||
                  post.authorUsername.toLowerCase() == 'asiimov') &&
              !_blockedUserIds.contains(post.authorID))
          .toList();

      if (mounted) {
        setState(() {
          _posts = fetchedPosts;
          _isLoading = false;
          _isLoadingMore = false;
          _hasMorePosts = snapshot.docs.length >= _limit;
        });
      }
    } catch (e) {
      debugPrint("Error fetching posts: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await _fetchPosts(refresh: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMorePosts) {
        setState(() {
          _isLoadingMore = true;
          _limit += 20;
        });
        _fetchPosts();
      }
    }
  }

  // NEW: Update only one post in the list (saves reads)
  Future<void> _updateSinglePost(String postId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
      if (doc.exists && mounted) {
        final newPost = Post.fromFirestore(doc);
        setState(() {
          final index = _posts.indexWhere((p) => p.id == postId);
          if (index != -1) {
            _posts[index] = newPost;
          }
        });
      }
    } catch (e) {
      debugPrint("Error updating single post: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : buildFeedList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreatePostPage(),
            ),
          );
          if (result == true) {
            _onRefresh();
          }
        },
        backgroundColor: Colors.orange,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }

  Widget buildFeedList() {
    if (_posts.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _posts.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _posts.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final post = _posts[index];
          return PostCard(
            key: ValueKey(post.id),
            post: post,
            currentUserId: currentUserId,
            onAction: () => _updateSinglePost(post.id),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PostDetailPage(
                    post: post,
                    docPath: 'posts/${post.id}',
                  ),
                ),
              );
              // Refresh this post in case comments or votes changed inside detail page
              _updateSinglePost(post.id);
            },
            onDelete: () async {
              await postService.deletePost(post.id);
              _onRefresh();
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: ListView( // Needed for RefreshIndicator to work on empty state
        shrinkWrap: true,
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.article_outlined,
                    size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                Text(
                  'No posts yet.\nFollow someone or be the first to post!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _onRefresh,
                  child: const Text("Refresh"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
