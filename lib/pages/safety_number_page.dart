import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// Dedicated, always-reachable screen (via the chat AppBar) showing the
/// safety number for a 1:1 conversation — the code the two participants
/// should compare through a separate channel (in person, phone call, a
/// different app) to detect a man-in-the-middle attack.
class SafetyNumberPage extends StatefulWidget {
  final String receiverID;
  final String receiverUsername;
  final Future<String> safetyNumberFuture;
  final Future<void> Function() onVerified;

  const SafetyNumberPage({
    super.key,
    required this.receiverID,
    required this.receiverUsername,
    required this.safetyNumberFuture,
    required this.onVerified,
  });

  @override
  State<SafetyNumberPage> createState() => _SafetyNumberPageState();
}

class _SafetyNumberPageState extends State<SafetyNumberPage> {
  bool _justVerified = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('safety_number_title'.tr()),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            children: [
              Icon(Icons.verified_user,
                  size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'safety_number_explanation'.tr(args: [widget.receiverUsername]),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              FutureBuilder<String>(
                future: widget.safetyNumberFuture,
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  if (snap.hasError || !snap.hasData) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'safety_number_unavailable'.tr(args: [widget.receiverUsername]),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    );
                  }
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      snap.data!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                        letterSpacing: 1.5,
                        height: 2.0,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                'safety_number_hint'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
              const Spacer(),
              if (_justVerified)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'safety_number_verified'.tr(),
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await widget.onVerified();
                    if (mounted) setState(() => _justVerified = true);
                  },
                  child: Text('safety_number_mark_verified'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
