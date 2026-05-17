import 'dart:async';
import 'package:asiimov/components/comment_tile.dart';
import 'package:asiimov/components/post_card.dart';
import 'package:asiimov/models/comment.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PostDetailPage extends StatefulWidget {
  final Post post;
  final String docPath;

  const PostDetailPage({super.key, required this.post, required this.docPath});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final TextEditingController _commentController = TextEditingController();
  final PostService _postService = PostService();
  final FocusNode _commentFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  int _commentLimit = 15;
  bool _isLoadingMore = false;

  List<Comment> _comments = [];
  bool _isCommentsLoading = true;
  late Post _post;
  Post? _parentPost;
  String? _parentDocPath;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _fetchComments();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _fetchComments({bool refresh = false}) async {
    // Always attempt to fetch parent post if this is a comment
    if (widget.docPath.contains('/comments/')) {
      final docRef = FirebaseFirestore.instance.doc(widget.docPath);
      final parentRef = docRef.parent.parent;
      if (parentRef != null) {
        _parentDocPath = parentRef.path;
        try {
          final parentDoc = await parentRef.get();
          if (parentDoc.exists && mounted) {
            setState(() {
              _parentPost = Post.fromFirestore(parentDoc);
            });
          }
        } catch (e) {
          debugPrint("Error fetching parent post: $e");
        }
      }
    }

    if (refresh) {
      _commentLimit = 15;
      // Also refresh the post itself if requested
      try {
        final postDoc = await FirebaseFirestore.instance.doc(widget.docPath).get();
        if (postDoc.exists) {
          setState(() {
            _post = Post.fromFirestore(postDoc);
          });
        }
      } catch (e) {
        debugPrint("Error refreshing post: $e");
      }
    }

    try {
      final snapshot = await _postService.getCommentsFuture(widget.docPath, _commentLimit);
      final fetchedComments = snapshot.docs
          .map((doc) => Comment.fromFirestore(doc))
          .toList();
      
      // Owner's comments always appear first.
      fetchedComments.sort((a, b) {
        final isAOwner = a.authorID == widget.post.authorID;
        final isBOwner = b.authorID == widget.post.authorID;

        if (isAOwner && !isBOwner) return -1;
        if (!isAOwner && isBOwner) return 1;

        final scoreA = a.upvotes.length - a.downvotes.length;
        final scoreB = b.upvotes.length - b.downvotes.length;
        return scoreB.compareTo(scoreA);
      });

      if (mounted) {
        setState(() {
          _comments = fetchedComments;
          _isCommentsLoading = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching comments: $e");
      if (mounted) {
        setState(() => _isCommentsLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    _fetchComments(refresh: true);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _comments.length >= _commentLimit) {
        setState(() {
          _isLoadingMore = true;
          _commentLimit += 15;
        });
        _fetchComments();
      }
    }
  }

  void _addComment() async {
    final String commentText = _commentController.text.trim();
    if (commentText.isEmpty) return;

    // Clear immediately for better UX
    _commentController.clear();
    _commentFocus.unfocus();

    await _postService.addComment(widget.docPath, commentText);
    
    // Refresh to show the new comment and update post comment count
    _onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService().getCurrentUser()!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        foregroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _onRefresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _onRefresh,
              child: _isCommentsLoading && _comments.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: 2 + _comments.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        // 0: Main Post (with embedded parent if applicable)
                        if (index == 0) {
                          return PostCard(
                            post: _post,
                            currentUserId: currentUserId,
                            docPath: widget.docPath,
                            parentPost: _parentPost,
                            parentDocPath: _parentDocPath,
                            onAction: _onRefresh,
                          );
                        }
                        // 1: Divider
                        if (index == 1) {
                          return Column(
                            children: [
                              Divider(
                                color: Theme.of(context).colorScheme.secondary,
                                height: 1,
                              ),
                              if (_comments.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Center(
                                    child: Text(
                                      'No comments yet.',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        }
                        
                        // Last: Loading Indicator
                        if (index == 2 + _comments.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        // Comments
                        final comment = _comments[index - 2];
                        return CommentTile(
                          comment: comment,
                          parentPath: widget.docPath,
                          currentUserId: currentUserId,
                          onAction: _onRefresh,
                        );
                      },
                    ),
            ),
          ),

          // Comment input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      focusNode: _commentFocus,
                      maxLength: 250,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Add a comment...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondary,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _addComment,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Colors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_upward,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
