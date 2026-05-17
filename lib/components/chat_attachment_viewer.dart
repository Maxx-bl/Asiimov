import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';

class ChatAttachmentViewer extends StatelessWidget {
  final Map<String, dynamic> attachment;
  final bool isDarkMode;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;

  const ChatAttachmentViewer({
    super.key,
    required this.attachment,
    required this.isDarkMode,
    this.onLongPress,
    this.onDoubleTap,
  });

  Future<void> _downloadOnly(BuildContext context, String url, String fileName) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Downloading $fileName...'), duration: const Duration(seconds: 1)),
      );

      Directory? dir;
      try {
        if (Platform.isAndroid) {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) {
             dir = await getDownloadsDirectory();
          }
        } else {
          dir = await getDownloadsDirectory();
        }
      } catch (e) {
        // Fallback
      }
      dir ??= await getApplicationDocumentsDirectory();
      
      final savePath = '${dir.path}/$fileName';

      final dio = Dio();
      await dio.download(url, savePath);
      final ext = fileName.split('.').last.toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        await ImageGallerySaverPlus.saveFile(savePath);
      }

      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Downloaded to Documents')),
      );
    } catch (e) {
      debugPrint("Error downloading file: $e");
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Failed to download file.')),
      );
    }
  }

  void _openImagePreview(BuildContext context, String url, String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ImagePreviewScreen(url: url, fileName: name),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final String type = attachment['type'] ?? 'document';
    final String url = attachment['url'] ?? '';
    final String name = attachment['name'] ?? 'attachment';
    final int size = attachment['size'] ?? 0;

    if (type == 'image') {
      return GestureDetector(
        onTap: () => _openImagePreview(context, url, name),
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 300, maxWidth: 250),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Hero(
            tag: url,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(color: Colors.orange),
                  ),
                ),
                errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
        ),
      );
    } else if (type == 'video') {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => MediaCarouselScreen(
                attachments: [attachment],
                initialIndex: 0,
              ),
            ),
          );
        },
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
        child: Container(
          height: 180,
          width: 220,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 50)),
              Positioned(
                bottom: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                  child: const Text('VIDEO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Document embed
      return GestureDetector(
        onTap: () => _downloadOnly(context, url, name),
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
        child: Container(
          width: 220,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey.shade900 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade400, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.insert_drive_file, size: 24, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatSize(size),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Tap to download", style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)),
                  const Icon(Icons.download_rounded, size: 14, color: Colors.blue),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }
}

class _ImagePreviewScreen extends StatelessWidget {
  final String url;
  final String fileName;

  const _ImagePreviewScreen({required this.url, required this.fileName});

  Future<void> _downloadImage(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Downloading $fileName...'), duration: const Duration(seconds: 1)),
      );

      Directory? dir;
      try {
        if (Platform.isAndroid) {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) {
             dir = await getDownloadsDirectory();
          }
        } else {
          dir = await getDownloadsDirectory();
        }
      } catch (e) {
        // Fallback
      }
      dir ??= await getApplicationDocumentsDirectory();
      
      final savePath = '${dir.path}/$fileName';

      final dio = Dio();
      await dio.download(url, savePath);
      final ext = fileName.split('.').last.toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        await ImageGallerySaverPlus.saveFile(savePath);
      }

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Downloaded to Documents')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Failed to download image.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: () => _downloadImage(context),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.1,
          maxScale: 4.0,
          child: Hero(
            tag: url,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              placeholder: (context, url) => const CircularProgressIndicator(color: Colors.orange),
              errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey, size: 50),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatVideoPlayer extends StatefulWidget {
  final String url;
  final String fileName;
  final VoidCallback onDownload;
  final bool isFullScreen;

  const _ChatVideoPlayer({required this.url, required this.fileName, required this.onDownload, this.isFullScreen = false});

  @override
  State<_ChatVideoPlayer> createState() => _ChatVideoPlayerState();
}

class _ChatVideoPlayerState extends State<_ChatVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        height: widget.isFullScreen ? double.infinity : 180,
        width: widget.isFullScreen ? double.infinity : 220,
        margin: widget.isFullScreen ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(widget.isFullScreen ? 0 : 12),
        ),
        child: const Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }

    return Container(
      constraints: widget.isFullScreen ? null : const BoxConstraints(maxHeight: 250, maxWidth: 220),
      width: widget.isFullScreen ? double.infinity : null,
      height: widget.isFullScreen ? double.infinity : null,
      margin: widget.isFullScreen ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.isFullScreen ? 0 : 12),
        color: Colors.black,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.isFullScreen ? 0 : 12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _controller.value.isPlaying ? _controller.pause() : _controller.play();
                  });
                },
                child: VideoPlayer(_controller),
              ),
            ),
            if (!_controller.value.isPlaying)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _controller.play();
                  });
                },
                child: Icon(
                  Icons.play_circle_filled,
                  color: Colors.white.withValues(alpha: 0.8),
                  size: widget.isFullScreen ? 64 : 48,
                ),
              ),
            if (!widget.isFullScreen)
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                  onPressed: widget.onDownload,
                ),
              ),
            if (widget.isFullScreen)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: Colors.orange),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatMediaGrid extends StatelessWidget {
  final List<dynamic> attachments;
  final bool isDarkMode;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;

  const ChatMediaGrid({
    super.key,
    required this.attachments,
    required this.isDarkMode,
    this.onLongPress,
    this.onDoubleTap,
  });

  void _openCarousel(BuildContext context, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MediaCarouselScreen(
          attachments: attachments,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  Widget _buildMediaItem(BuildContext context, Map<String, dynamic> attachment, int index, {bool isOverlay = false, int extraCount = 0}) {
    final String type = attachment['type'] ?? 'image';
    final String url = attachment['url'] ?? '';

    Widget content;
    if (type == 'video') {
      content = Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 40)),
        ],
      );
    } else {
      content = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey.shade800),
        errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
      );
    }

    return GestureDetector(
      onTap: () => _openCarousel(context, index),
      onLongPress: onLongPress,
      onDoubleTap: onDoubleTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(tag: url, child: content),
            if (isOverlay && extraCount > 0)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Text('+$extraCount', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (attachments.length == 1) {
      // Single attachment: show normally
      return ChatAttachmentViewer(
        attachment: Map<String, dynamic>.from(attachments.first),
        isDarkMode: isDarkMode,
        onLongPress: onLongPress,
        onDoubleTap: onDoubleTap,
      );
    }

    final int displayCount = attachments.length > 4 ? 4 : attachments.length;
    final int extraCount = attachments.length - 4;

    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: displayCount,
        itemBuilder: (context, index) {
          final attachment = Map<String, dynamic>.from(attachments[index]);
          return _buildMediaItem(context, attachment, index, isOverlay: index == 3, extraCount: extraCount);
        },
      ),
    );
  }
}

class MediaCarouselScreen extends StatefulWidget {
  final List<dynamic> attachments;
  final int initialIndex;

  const MediaCarouselScreen({super.key, required this.attachments, required this.initialIndex});

  @override
  State<MediaCarouselScreen> createState() => _MediaCarouselScreenState();
}

class _MediaCarouselScreenState extends State<MediaCarouselScreen> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _downloadMedia(BuildContext context, Map<String, dynamic> attachment) async {
    final String url = attachment['url'] ?? '';
    final String fileName = attachment['name'] ?? 'media_file';
    
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Downloading $fileName...'), duration: const Duration(seconds: 1)),
      );

      Directory? dir;
      try {
        if (Platform.isAndroid) {
          dir = Directory('/storage/emulated/0/Download');
          if (!await dir.exists()) {
             dir = await getDownloadsDirectory();
          }
        } else {
          dir = await getDownloadsDirectory();
        }
      } catch (e) {
        // Fallback
      }
      dir ??= await getApplicationDocumentsDirectory();
      
      final savePath = '${dir.path}/$fileName';

      final dio = Dio();
      await dio.download(url, savePath);
      final ext = fileName.split('.').last.toLowerCase();
      if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'mp4', 'mov', 'avi', 'mkv'].contains(ext)) {
        await ImageGallerySaverPlus.saveFile(savePath);
      }

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Downloaded to Documents')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Failed to download media.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.attachments.length,
        itemBuilder: (context, index) {
          final attachment = Map<String, dynamic>.from(widget.attachments[index]);
          final String type = attachment['type'] ?? 'image';
          final String url = attachment['url'] ?? '';

          Widget content;
          if (type == 'video') {
             content = Center(
               child: _ChatVideoPlayer(url: url, fileName: attachment['name'] ?? 'video', onDownload: () {}, isFullScreen: true),
             );
          } else {
             content = InteractiveViewer(
                minScale: 0.1,
                maxScale: 4.0,
                child: Hero(
                  tag: url,
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const CircularProgressIndicator(color: Colors.orange),
                    errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey, size: 50),
                  ),
                ),
              );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              Center(child: content),
              Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                  icon: const Icon(Icons.download_rounded, color: Colors.white, size: 30),
                  onPressed: () => _downloadMedia(context, attachment),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
