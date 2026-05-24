import 'dart:io';
import 'package:asiimov/services/file/file_service.dart';
import 'package:asiimov/services/image/image_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:easy_localization/easy_localization.dart';

class PickedAttachment {
  final File file;
  final bool isVideo;
  final VideoPlayerController? videoController;

  PickedAttachment({
    required this.file,
    required this.isVideo,
    this.videoController,
  });
}

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final TextEditingController _controller = TextEditingController();
  final int _maxLength = 250;
  bool _isPosting = false;

  final List<PickedAttachment> _attachments = [];

  @override
  void dispose() {
    _controller.dispose();
    for (final att in _attachments) {
      att.videoController?.dispose();
    }
    super.dispose();
  }

  void _pickMedia() async {
    if (_isPosting) return;

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
              Text(
                'Add Photos or Videos',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                ),
                title: Text('take_a_photo'.tr()),
                onTap: () => Navigator.pop(context, 'camera_photo'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.deepOrange,
                  child: Icon(Icons.videocam, color: Colors.white),
                ),
                title: Text('record_a_video'.tr()),
                onTap: () => Navigator.pop(context, 'camera_video'),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  child: const Icon(Icons.photo_library, color: Colors.white),
                ),
                title: Text('choose_from_gallery'.tr()),
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
      for (final a in _attachments) {
        currentTotalSize += await a.file.length();
      }

      for (final pickedXFile in pickedXFiles) {
        final ext = pickedXFile.path.toLowerCase();
        final bool isVideo = isCamVideo || ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi') || ext.endsWith('.mkv');
        final bool validImage = ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png') || ext.endsWith('.gif') || ext.endsWith('.webp');

        if (!isVideo && !validImage) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('skipped_unsupported_file_forma'.tr()), backgroundColor: Colors.redAccent),
            );
          }
          continue;
        }

        final file = File(pickedXFile.path);
        final length = await file.length();

        if (currentTotalSize + length > FileService.maxFileSizeInBytes) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('total_size_exceeds_the_20mb_li'.tr()), backgroundColor: Colors.redAccent),
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
                SnackBar(content: Text('video_duration_cannot_exceed_1'.tr()), backgroundColor: Colors.redAccent),
              );
            }
            continue;
          }
          vc.setLooping(true);
          vc.play();
          setState(() {
            _attachments.add(PickedAttachment(file: finalFile, isVideo: true, videoController: vc));
          });
        } else {
          setState(() {
            _attachments.add(PickedAttachment(file: finalFile, isVideo: false));
          });
        }
      }
    } catch (e) {
      debugPrint("Error picking media: $e");
    }
  }

  void _removeAttachment(int index) {
    final att = _attachments[index];
    att.videoController?.dispose();
    setState(() {
      _attachments.removeAt(index);
    });
  }

  Future<bool?> _showAudienceSelection(bool isPublic) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final primaryColor = Theme.of(context).primaryColor;
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'choose_audience'.tr(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Who should see this post?',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.primary.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              // Option: Everyone / Followers
              InkWell(
                onTap: () => Navigator.pop(context, false),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.secondary,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isPublic ? Icons.public_rounded : Icons.group_rounded,
                          color: primaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPublic ? 'everyone'.tr() : 'followers'.tr(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isPublic
                                  ? 'Anyone on Glyphe can see this post.'
                                  : 'Only your followers can see this post.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Option: Close Friends
              InkWell(
                onTap: () => Navigator.pop(context, true),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.secondary,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.greenAccent.shade400.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.shade400.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.people_alt_rounded,
                          color: Colors.greenAccent.shade700,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Close Friends',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Only selected close friends can see this post.',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _post() async {
    if ((_controller.text.trim().isEmpty && _attachments.isEmpty) || _isPosting) return;

    setState(() => _isPosting = true);
    final cleanContent = _controller.text.trim().replaceAll(RegExp(r'(\r?\n){2,}'), '\n');
    
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) throw Exception("User not authenticated.");

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUserId).get();
      if (!userDoc.exists) throw Exception("User data not found.");

      final userData = userDoc.data() ?? {};
      final bool isCFEnabled = userData['closeFriendsEnabled'] ?? false;
      final List<String> cfList = List<String>.from(userData['closeFriends'] ?? []);
      final bool isPublic = userData['public_account'] ?? false;

      bool isCloseFriendsOnly = false;
      List<String> visibleTo = [];

      if (isCFEnabled) {
        final bool? chosen = await _showAudienceSelection(isPublic);
        if (chosen == null) {
          setState(() => _isPosting = false);
          return;
        }
        isCloseFriendsOnly = chosen;
        if (isCloseFriendsOnly) {
          visibleTo = cfList;
        }
      }

      List<dynamic> uploadedAttachments = [];
      for (final att in _attachments) {
        final attachmentMap = await FileService().uploadChatAttachment(att.file, 'post');
        if (attachmentMap != null) {
          uploadedAttachments.add(attachmentMap);
        } else {
          throw Exception('Failed to upload attachment.');
        }
      }

      await PostService().createPost(
        cleanContent,
        attachments: uploadedAttachments.isNotEmpty ? uploadedAttachments : null,
        isCloseFriendsOnly: isCloseFriendsOnly,
        visibleTo: visibleTo,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isPosting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        foregroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                final isValid =
                    (value.text.trim().isNotEmpty || _attachments.isNotEmpty) && value.text.length <= _maxLength;
                return TextButton(
                  onPressed: isValid && !_isPosting ? _post : null,
                  style: TextButton.styleFrom(
                    backgroundColor:
                        isValid ? Theme.of(context).primaryColor : Theme.of(context).primaryColor.withValues(alpha: 0.3),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _isPosting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'post_button'.tr(),
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                );
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                maxLength: _maxLength,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'whats_on_your_mind'.tr().tr(),
                  border: InputBorder.none,
                  counterText: '',
                ),
                style: const TextStyle(fontSize: 18),
              ),
            ),

            if (_attachments.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  itemBuilder: (context, index) {
                    final att = _attachments[index];
                    return Container(
                      width: 120,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).primaryColor, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
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
                              Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 28)),
                            Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: CircleAvatar(
                                  backgroundColor: Colors.black87,
                                  radius: 14,
                                  child: IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: const Icon(Icons.close, color: Colors.white, size: 14),
                                    onPressed: () => _removeAttachment(index),
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

            // Bottom toolbar
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.image, color: Theme.of(context).primaryColor, size: 28),
                    onPressed: !_isPosting ? _pickMedia : null,
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, child) {
                      final remaining = _maxLength - value.text.length;
                      Color counterColor;
                      if (remaining < 0) {
                        counterColor = Colors.red;
                      } else if (remaining < 30) {
                        counterColor = Theme.of(context).primaryColor;
                      } else {
                        counterColor = Colors.grey;
                      }

                      return Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              value: (value.text.length / _maxLength).clamp(0, 1),
                              strokeWidth: 2.5,
                              backgroundColor: Colors.grey.shade300,
                              color: remaining < 0
                                  ? Colors.red
                                  : remaining < 30
                                      ? Theme.of(context).primaryColor
                                      : Theme.of(context).primaryColor.withValues(alpha: 0.3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$remaining',
                            style: TextStyle(
                              color: counterColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

