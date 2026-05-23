import 'package:asiimov/services/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// Shows a confirmation dialog and signs out if the user confirms.
Future<void> confirmAndSignOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('log_out'.tr()),
      content: Text('are_you_sure_you_want_to_sign_'.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text('cancel'.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            'log_out'.tr(),
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
