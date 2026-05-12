import 'package:asiimov/components/username_display.dart';
import 'package:flutter/material.dart';

class UserTile extends StatelessWidget {
  final String text;
  final String? userId;
  final void Function()? onTap;
  final Widget? trailing;
  final Widget? subtitle;
  final Widget? leading;

  const UserTile({
    super.key,
    required this.text,
    this.userId,
    required this.onTap,
    this.trailing,
    this.subtitle,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: leading ?? CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        child: Icon(
          Icons.person,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: (userId != null && userId!.isNotEmpty)
          ? UsernameDisplay(
              userId: userId!,
              username: text,
              style: const TextStyle(fontWeight: FontWeight.bold),
            )
          : Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
      subtitle: subtitle,
      trailing: trailing,
    );
  }
}
