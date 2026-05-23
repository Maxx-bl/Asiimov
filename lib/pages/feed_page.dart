import 'dart:async';

import 'package:asiimov/components/post_card.dart';
import 'package:asiimov/components/user_tile.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/pages/create_post_page.dart';
import 'package:asiimov/pages/post_detail_page.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final PostService postService = PostService();
  final UserService userService = UserService();
  final ChatService chatService = ChatService();
  final String currentUserId = AuthService().getCurrentUser()!.uid;

  final ScrollController _scrollController = ScrollController();
  List<Post> _posts = [];
  int _limit = 20;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMorePosts = true;
  List<String> _blockedUserIds = [];
  List<String> _allowedUserIds = [];

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = "";
  Timer? _debounce;
  final FocusNode _searchFocusNode = FocusNode();

  final ScrollController _searchScrollController = ScrollController();
  int _searchLimit = 20;
  bool _isLoadingMoreSearch = false;

  @override
  void initState() {
    super.initState();
    _initializeFeed();
    _scrollController.addListener(_onScroll);
    _searchScrollController.addListener(_onSearchScroll);
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
          .where((post) {
            // Blocked?
            if (_blockedUserIds.contains(post.authorID)) return false;

            // Close Friends Filter
            if (post.isCloseFriendsOnly) {
              if (post.authorID != currentUserId && !post.visibleTo.contains(currentUserId)) {
                return false;
              }
            }

            // Normal feed rules
            return _allowedUserIds.contains(post.authorID) ||
                post.authorUsername.toLowerCase() == 'asiimov';
          })
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
    _searchScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchScroll() {
    if (_searchScrollController.position.pixels >=
        _searchScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMoreSearch && _isSearching) {
        setState(() {
          _isLoadingMoreSearch = true;
          _searchLimit += 20;
        });
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) setState(() => _isLoadingMoreSearch = false);
        });
      }
    }
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
      _searchLimit = 20;
    });
    Future.microtask(() => _searchFocusNode.requestFocus());
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = "";
      _searchController.clear();
      _searchLimit = 20;
    });
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

  Widget buildSearchList() {
    return StreamBuilder<DocumentSnapshot>(
      stream: userService.getUserStream(currentUserId),
      builder: (context, userSnapshot) {
        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
        final following = List<String>.from(userData?['following'] ?? []);

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: chatService.getUsersStreamExcludingBlocked(limit: _searchLimit),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text("Error"));
            if (snapshot.connectionState == ConnectionState.waiting &&
                _searchLimit == 20) {
              return Center(child: CircularProgressIndicator());
            }

            final users = snapshot.data ?? [];
            final filteredUsers = users.where((u) {
              final username = u['username'].toString().toLowerCase();
              final matchesQuery =
                  _searchQuery.isEmpty || username.contains(_searchQuery);
              final isFollowing = following.contains(u['uid']);
              return (_searchQuery.isEmpty ? isFollowing : matchesQuery);
            }).toList();

            if (filteredUsers.isEmpty &&
                snapshot.connectionState != ConnectionState.waiting) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(
                      "No user found",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              controller: _searchScrollController,
              itemCount: filteredUsers.length + (_isLoadingMoreSearch ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == filteredUsers.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final u = filteredUsers[index];
                return UserTile(
                  text: u['username'],
                  userId: u['uid'],
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProfilePage(
                          userId: u['uid'],
                          username: u['username'],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'search_user'.tr().tr(),
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
                onChanged: (value) {
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    setState(() {
                      _searchQuery = value.trim().toLowerCase();
                      _searchLimit = 20;
                    });
                  });
                },
              )
            : Text(
                'A S I I M O V',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
              ),
        foregroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          _isSearching
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _stopSearch,
                )
              : IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _startSearch,
                ),
        ],
      ),
      body: _isSearching
          ? buildSearchList()
          : (_isLoading ? Center(child: CircularProgressIndicator()) : buildFeedList()),
      floatingActionButton: _isSearching
          ? null
          : Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColor.withValues(alpha: 0.85),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () async {
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
                  child: const Icon(
                    Icons.history_edu_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
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
                  child: Text("Refresh"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
