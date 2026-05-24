import 'package:flutter/material.dart';
import 'theme_settings_page.dart';
import 'privacy_settings_page.dart';
import 'close_friends_page.dart';
import 'security_settings_page.dart';
import 'notification_settings_page.dart';
import 'blocked_users_page.dart';
import 'language_settings_page.dart';
import 'support_page.dart';
import 'package:easy_localization/easy_localization.dart';
import 'about_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('settings'.tr()),
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
                icon: Icons.language_outlined,
                title: 'language'.tr().tr(),
                destination: const LanguageSettingsPage(),
              ),

              SettingCategoryTile(
                icon: Icons.palette_outlined,
                title: 'theme'.tr().tr(),
                destination: const ThemeSettingsPage(),
              ),
              
              SettingCategoryTile(
                icon: Icons.lock_person_outlined,
                title: 'privacy'.tr().tr(),
                destination: const PrivacySettingsPage(),
              ),

              SettingCategoryTile(
                icon: Icons.people_alt_rounded,
                title: 'close_friends'.tr().tr(),
                destination: const CloseFriendsPage(),
              ),
              
              SettingCategoryTile(
                icon: Icons.security_outlined,
                title: 'security'.tr().tr(),
                destination: const SecuritySettingsPage(),
              ),
              
              SettingCategoryTile(
                icon: Icons.notifications_none_rounded,
                title: 'notifications'.tr().tr(),
                destination: const NotificationSettingsPage(),
              ),
              
              SettingCategoryTile(
                icon: Icons.block_flipped,
                title: 'blocked_users'.tr().tr(),
                destination: BlockedUsersPage(),
              ),

              SettingCategoryTile(
                icon: Icons.help_outline_rounded,
                title: 'help'.tr(),
                destination: const SupportPage(),
              ),

              SettingCategoryTile(
                icon: Icons.info_outline_rounded,
                title: 'about'.tr(),
                destination: const AboutPage(),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingCategoryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget destination;

  const SettingCategoryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.destination,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
        ),
      ),
      margin: const EdgeInsets.only(left: 25, top: 12, right: 25),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Icon(
          icon,
          size: 26, // Slightly larger than typical notification icon size (20)
          color: Theme.of(context).primaryColor,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => destination),
          );
        },
      ),
    );
  }
}
