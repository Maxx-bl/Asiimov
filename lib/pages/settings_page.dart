import 'package:flutter/material.dart';
import 'theme_settings_page.dart';
import 'privacy_settings_page.dart';
import 'close_friends_page.dart';
import 'security_settings_page.dart';
import 'notification_settings_page.dart';
import 'blocked_users_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Settings'),
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
                icon: Icons.palette_outlined,
                title: 'Theme',
                destination: const ThemeSettingsPage(),
              ),
              
              SettingCategoryTile(
                icon: Icons.lock_person_outlined,
                title: 'Privacy',
                destination: const PrivacySettingsPage(),
              ),

              SettingCategoryTile(
                icon: Icons.people_alt_rounded,
                title: 'Close Friends',
                destination: const CloseFriendsPage(),
              ),
              
              SettingCategoryTile(
                icon: Icons.security_outlined,
                title: 'Security',
                destination: const SecuritySettingsPage(),
              ),
              
              SettingCategoryTile(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                destination: const NotificationSettingsPage(),
              ),
              
              SettingCategoryTile(
                icon: Icons.block_flipped,
                title: 'Blocked Users',
                destination: BlockedUsersPage(),
              ),
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
