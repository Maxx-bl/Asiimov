import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:asiimov/services/update/update_service.dart';
import 'package:asiimov/pages/force_update_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateGate extends StatefulWidget {
  final Widget child;

  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  final UpdateService _updateService = UpdateService();
  bool _isLoading = true;
  UpdateStatus _status = UpdateStatus.upToDate;
  String _downloadUrl = '';

  @override
  void initState() {
    super.initState();
    _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    await _updateService.initialize();
    final status = await _updateService.getUpdateStatus();
    
    if (mounted) {
      setState(() {
        _status = status;
        _downloadUrl = _updateService.downloadUrl;
        _isLoading = false;
      });

      if (status == UpdateStatus.recommended) {
        _showRecommendedUpdateDialog();
      }
    }
  }

  Future<void> _showRecommendedUpdateDialog() async {
    // Check if user recently dismissed
    final prefs = await SharedPreferences.getInstance();
    final lastDismissedStr = prefs.getString('last_recommended_update_dismissed');
    
    if (lastDismissedStr != null) {
      final lastDismissed = DateTime.parse(lastDismissedStr);
      // If dismissed less than 24 hours ago, don't show again
      if (DateTime.now().difference(lastDismissed).inHours < 24) {
        return;
      }
    }

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            'update_recommended_title'.tr(),
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          content: Text(
            'update_recommended_desc'.tr(),
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await prefs.setString('last_recommended_update_dismissed', DateTime.now().toIso8601String());
                if (mounted) Navigator.pop(context);
              },
              child: Text(
                'later'.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)),
              ),
            ),
            TextButton(
              onPressed: () async {
                if (_downloadUrl.isNotEmpty) {
                  final Uri url = Uri.parse(_downloadUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                }
                if (mounted) Navigator.pop(context);
              },
              child: Text(
                'update_now'.tr(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ),
      );
    }

    if (_status == UpdateStatus.required) {
      return ForceUpdatePage(downloadUrl: _downloadUrl);
    }

    return widget.child;
  }
}
