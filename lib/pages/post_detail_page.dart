import 'dart:async';
import 'dart:io';
import 'package:asiimov/components/comment_tile.dart';
import 'package:asiimov/components/post_card.dart';
import 'package:asiimov/models/comment.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/pages/create_post_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/file/file_service.dart';
import 'package:asiimov/services/image/image_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

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

  final List<PickedAttachment> _commentAttachments = [];
  bool _isPostingComment = false;

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
    for (final att in _commentAttachments) {
      att.videoController?.dispose();
    }
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

  void _pickCommentMedia() async {
    if (_isPostingComment) return;

    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Add Photos or Videos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: const Text('Take a Photo'),
                onTap: () => Navigator.pop(context, 'camera_photo'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.deepOrange,
                  child: Icon(Icons.videocam, color: Colors.white),
                ),
                title: const Text('Record a Video'),
                onTap: () => Navigator.pop(context, 'camera_video'),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  child: const Icon(Icons.photo_library, color: Colors.white),
                ),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final ImagePicker picker = ImagePicker();
    List<XFile> pickedXFiles = [];
    bool isCamVideo = false;

    try {
      if (source == 'camera_photo') {
        final xf = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (xf != null) pickedXFiles.add(xf);
      } else if (source == 'camera_video') {
        final xf = await picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 10));
        if (xf != null) {
          pickedXFiles.add(xf);
          isCamVideo = true;
        }
      } else if (source == 'gallery') {
        final list = await picker.pickMultipleMedia();
        if (list.isNotEmpty) pickedXFiles.addAll(list);
      }

      if (pickedXFiles.isEmpty) return;

      int currentTotalSize = 0;
      for (final a in _commentAttachments) {
        currentTotalSize += await a.file.length();
      }

      for (final pickedXFile in pickedXFiles) {
        final ext = pickedXFile.path.toLowerCase();
        final bool isVideo = isCamVideo || ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi') || ext.endsWith('.mkv');
        final bool validImage = ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png') || ext.endsWith('.gif') || ext.endsWith('.webp');

        if (!isVideo && !validImage) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Skipped unsupported file format.'), backgroundColor: Colors.redAccent),
            );
          }
          continue;
        }

        final file = File(pickedXFile.path);
        final length = await file.length();

        if (currentTotalSize + length > FileService.maxFileSizeInBytes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Total size exceeds the 20MB limit.'), backgroundColor: Colors.redAccent),
            );
          }
          break;
        }

        File finalFile = file;
        if (!isVideo) {
          final compressed = await ImageService().compressImage(file);
          if (compressed != null) finalFile = compressed;
        }

        currentTotalSize += await finalFile.length();

        if (isVideo) {
          final vc = VideoPlayerController.file(finalFile);
          await vc.initialize();
          if (vc.value.duration.inSeconds > 10) {
            vc.dispose();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Video duration cannot exceed 10 seconds.'), backgroundColor: Colors.redAccent),
              );
            }
            continue;
          }
          vc.setLooping(true);
          vc.play();
          setState(() {
            _commentAttachments.add(PickedAttachment(file: finalFile, isVideo: true, videoController: vc));
          });
        } else {
          setState(() {
            _commentAttachments.add(PickedAttachment(file: finalFile, isVideo: false));
          });
        }
      }
    } catch (e) {
      debugPrint("Error picking comment media: $e");
    }
  }

  void _removeCommentAttachment(int index) {
    final att = _commentAttachments[index];
    att.videoController?.dispose();
    setState(() {
      _commentAttachments.removeAt(index);
    });
  }

  void _addComment() async {
    final String commentText = _commentController.text.trim();
    if ((commentText.isEmpty && _commentAttachments.isEmpty) || _isPostingComment) return;

    setState(() => _isPostingComment = true);

    try {
      List<dynamic> uploadedAttachments = [];
      for (final att in _commentAttachments) {
        final attachmentMap = await FileService().uploadChatAttachment(att.file, 'comment');
        if (attachmentMap != null) {
          uploadedAttachments.add(attachmentMap);
        } else {
          throw Exception('Failed to upload attachment.');
        }
      }

      _commentController.clear();
      _commentFocus.unfocus();
      for (final att in _commentAttachments) {
        att.videoController?.dispose();
      }
      setState(() {
        _commentAttachments.clear();
      });

      await _postService.addComment(widget.docPath, commentText, uploadedAttachments.isNotEmpty ? uploadedAttachments : null);
      
      if (mounted) {
        setState(() => _isPostingComment = false);
        _onRefresh();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPostingComment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.redAccent),
        );
      }
    }
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_commentAttachments.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _commentAttachments.length,
                        itemBuilder: (context, index) {
                          final att = _commentAttachments[index];
                          return Container(
                            width: 100,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).primaryColor, width: 1.5),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  att.isVideo && att.videoController != null
                                      ? FittedBox(
                                          fit: BoxFit.cover,
                                          child: SizedBox(
                                            width: att.videoController!.value.size.width,
                                            height: att.videoController!.value.size.height,
                                            child: VideoPlayer(att.videoController!),
                                          ),
                                        )
                                      : Image.file(att.file, fit: BoxFit.cover),
                                  if (att.isVideo)
                                    const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 24)),
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: CircleAvatar(
                                        backgroundColor: Colors.black87,
                                        radius: 12,
                                        child: IconButton(
                                          padding: EdgeInsets.zero,
                                          icon: const Icon(Icons.close, color: Colors.white, size: 14),
                                          onPressed: () => _removeCommentAttachment(index),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.image, color: Theme.of(context).primaryColor),
                        onPressed: !_isPostingComment ? _pickCommentMedia : null,
                      ),
                      const SizedBox(width: 4),
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
                            counterText: '',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _isPostingComment
                          ? SizedBox(
                              width: 36,
                              height: 36,
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor),
                              ),
                            )
                          : GestureDetector(
                              onTap: _addComment,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.arrow_upward,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                    ],
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

