import 'package:asiimov/components/comment_tile.dart';
import 'package:asiimov/components/post_card.dart';
import 'package:asiimov/models/comment.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:flutter/material.dart';

class PostDetailPage extends StatefulWidget {
  final Post post;

  const PostDetailPage({super.key, required this.post});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final TextEditingController _commentController = TextEditingController();
  final PostService _postService = PostService();
  final FocusNode _commentFocus = FocusNode();

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  void _addComment() async {
    if (_commentController.text.trim().isEmpty) return;
    await _postService.addComment(
        widget.post.id, _commentController.text.trim());
    _commentController.clear();
    _commentFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService().getCurrentUser()!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Post (live stream for vote updates)
                  StreamBuilder(
                    stream: _postService.getPostsStream(),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        final docs = snapshot.data!.docs;
                        final postDoc = docs
                            .where((d) => d.id == widget.post.id)
                            .toList();
                        if (postDoc.isNotEmpty) {
                          final livePost = Post.fromFirestore(postDoc.first);
                          return PostCard(
                            post: livePost,
                            currentUserId: currentUserId,
                          );
                        }
                      }
                      return PostCard(
                        post: widget.post,
                        currentUserId: currentUserId,
                      );
                    },
                  ),

                  Divider(
                    color: Theme.of(context).colorScheme.secondary,
                    height: 1,
                  ),

                  // Comments
                  StreamBuilder(
                    stream: _postService.getCommentsStream(widget.post.id),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Error loading comments.'),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final comments = snapshot.data!.docs
                          .map((doc) => Comment.fromFirestore(doc))
                          .toList();

                      if (comments.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No comments yet.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          return CommentTile(
                            comment: comments[index],
                            postId: widget.post.id,
                            currentUserId: currentUserId,
                          );
                        },
                      );
                    },
                  ),
                ],
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
