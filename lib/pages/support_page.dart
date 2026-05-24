import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'settings_page.dart';
import 'support_tickets_page.dart';

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('help'.tr()),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            children: [
              const SizedBox(height: 10),
              SettingCategoryTile(
                icon: Icons.support_agent_rounded,
                title: 'contact_support'.tr(),
                destination: const SupportTicketsPage(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
