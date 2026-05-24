import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:asiimov/components/my_button.dart';

class ForceUpdatePage extends StatelessWidget {
  final String downloadUrl;

  const ForceUpdatePage({super.key, required this.downloadUrl});

  Future<void> _launchURL() async {
    if (downloadUrl.isNotEmpty) {
      final Uri url = Uri.parse(downloadUrl);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Could not launch $url');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.system_update_rounded,
                size: 100,
                color: Theme.of(context).colorScheme.primary, // Or use the dominant color which might be tertiary
              ),
              const SizedBox(height: 40),
              Text(
                'update_required_title'.tr(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'update_required_desc'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 50),
              MyButton(
                text: 'update_now'.tr(),
                onTap: _launchURL,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
