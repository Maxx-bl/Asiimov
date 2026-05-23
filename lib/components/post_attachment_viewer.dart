import 'package:asiimov/components/chat_attachment_viewer.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PostAttachmentViewer extends StatelessWidget {
  final List<dynamic> attachments;

  const PostAttachmentViewer({super.key, required this.attachments});

  Widget _buildSingleAttachment(BuildContext context, Map<String, dynamic> attachment) {
    final String type = attachment['type'] ?? 'image';
    final String url = attachment['url'] ?? '';
    final bool isVideo = type == 'video';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MediaCarouselScreen(
              attachments: attachments,
              initialIndex: 0,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        height: 220,
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.secondary, width: 1),
          color: Colors.black12,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: isVideo
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Center(
                        child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor),
                      ),
                      errorWidget: (context, url, error) => Center(
                        child: Icon(Icons.video_file, size: 40, color: Colors.grey),
                      ),
                    ),
                    Container(color: Colors.black26),
                    Center(
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        radius: 24,
                        child: Icon(Icons.play_arrow, color: Colors.white, size: 30),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'VIDEO',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                )
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).primaryColor),
                  ),
                  errorWidget: (context, url, error) => Center(
                    child: Icon(Icons.broken_image, size: 40, color: Colors.grey),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, Map<String, dynamic> attachment, int index, int totalCount) {
    final String type = attachment['type'] ?? 'image';
    final String url = attachment['url'] ?? '';
    final bool isVideo = type == 'video';

    final bool isOverlay = index == 3 && totalCount > 4;
    final int extraCount = totalCount - 4;

    Widget content;
    if (isVideo) {
      content = Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: Colors.black12),
            errorWidget: (context, url, error) => Center(child: Icon(Icons.video_file, color: Colors.grey)),
          ),
          Container(color: Colors.black26),
          Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 36)),
        ],
      );
    } else {
      content = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.black12),
        errorWidget: (context, url, error) => Center(child: Icon(Icons.broken_image, color: Colors.grey)),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => MediaCarouselScreen(
              attachments: attachments,
              initialIndex: index,
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (isOverlay)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Text(
                    '+$extraCount',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    if (attachments.length == 1) {
      return _buildSingleAttachment(context, Map<String, dynamic>.from(attachments.first));
    }

    final int displayCount = attachments.length > 4 ? 4 : attachments.length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.secondary, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 2,
            mainAxisSpacing: 2,
            childAspectRatio: 1.0,
          ),
          itemCount: displayCount,
          itemBuilder: (context, index) {
            final attachment = Map<String, dynamic>.from(attachments[index]);
            return _buildGridItem(context, attachment, index, attachments.length);
          },
        ),
      ),
    );
  }
}
