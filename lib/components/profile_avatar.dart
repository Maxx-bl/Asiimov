import 'package:asiimov/services/image/image_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A reusable avatar widget that loads profile pictures with caching.
/// Falls back to the user's initial letter if no picture is available.
class ProfileAvatar extends StatelessWidget {
  final String userId;
  final String username;
  final double radius;
  final bool showEditIcon;
  final VoidCallback? onTap;

  const ProfileAvatar({
    super.key,
    required this.userId,
    required this.username,
    this.radius = 18,
    this.showEditIcon = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: FutureBuilder<String?>(
        future: ImageService().getProfilePictureUrl(userId),
        builder: (context, snapshot) {
          final url = snapshot.data;

          return Stack(
            children: [
              CircleAvatar(
                radius: radius,
                backgroundColor: Colors.orange.withValues(alpha: 0.2),
                backgroundImage: url != null && url.isNotEmpty
                    ? CachedNetworkImageProvider(url)
                    : null,
                child: url == null || url.isEmpty
                    ? Text(
                        username.isNotEmpty
                            ? username[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: radius * 0.8,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      )
                    : null,
              ),
              if (showEditIcon)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.camera_alt,
                      size: radius * 0.35,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
