import 'package:flutter/material.dart';
import 'package:asiimov/widgets/safe_network_image.dart';
class GroupIcon extends StatelessWidget {
  final double size;
  final String? imageUrl;
  const GroupIcon({super.key, this.size = 40, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size / 2),
          child: SafeNetworkImage(
            url: imageUrl!,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return _buildDefaultIcon(context);
  }

  Widget _buildDefaultIcon(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.secondary,
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.40),
          width: 0.5,
        ),
      ),
      child: Icon(
        Icons.group_outlined,
        size: size * 0.50,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.70),
      ),
    );
  }
}
