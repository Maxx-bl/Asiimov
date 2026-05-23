import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// Compact dialog to collect a report reason (max 100 characters).
class ReportReasonDialog {
  static const int maxLength = 100;

  static Future<String?> show(
    BuildContext context, {
    required String title,
  }) {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final trimmed = controller.text.trim();
            final canSubmit = trimmed.isNotEmpty;

            return AlertDialog(
              title: Text(title, style: const TextStyle(fontSize: 18)),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why are you reporting this?',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      maxLength: maxLength,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'describe_the_issue'.tr().tr(),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.all(12),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('cancel'.tr()),
                ),
                TextButton(
                  onPressed: canSubmit
                      ? () => Navigator.pop(dialogContext, trimmed)
                      : null,
                  child: Text(
                    'Report',
                    style: TextStyle(
                      color: canSubmit
                          ? Theme.of(dialogContext).primaryColor
                          : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
