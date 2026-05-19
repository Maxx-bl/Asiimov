import 'package:asiimov/services/auth/auth_service.dart';
import 'package:flutter/material.dart';

/// Shows a confirmation dialog and signs out if the user confirms.
Future<void> confirmAndSignOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Log out'),
      content: const Text('Are you sure you want to sign out?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            'Log out',
            style: TextStyle(
              color: Theme.of(dialogContext).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    await AuthService().signOut();
  }
}
