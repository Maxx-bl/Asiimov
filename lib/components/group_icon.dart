import 'package:flutter/material.dart';

class GroupIcon extends StatelessWidget {
  final double size;
  const GroupIcon({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          // Background man (slightly offset and transparent)
          Positioned(
            right: size * 0.05,
            top: size * 0.05,
            child: Icon(
              Icons.person,
              size: size * 0.75,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
            ),
          ),
          // Foreground man
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person,
                size: size * 0.75,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
