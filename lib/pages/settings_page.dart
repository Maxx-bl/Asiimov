import 'package:asiimov/pages/notification_settings_page.dart';
import 'package:asiimov/themes/theme_provider.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'blocked_users_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: StreamBuilder<DocumentSnapshot>(
            stream: UserService().getUserStream(FirebaseAuth.instance.currentUser!.uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              final userData = snapshot.data?.data() as Map<String, dynamic>?;
              final isPublic = userData?['public_account'] ?? false; // Private by default
              final is2faEnabled = userData?['two_factor_enabled'] ?? false;

              return Column(
                children: [
                  //dark mode
                  Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary,
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.only(left: 25, top: 10, right: 25),
                    padding: const EdgeInsets.only(
                        left: 25, right: 25, top: 20, bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Dark mode'),
                        CupertinoSwitch(
                          value: Provider.of<ThemeProvider>(context, listen: false)
                              .isDarkMode,
                          activeTrackColor: Colors.orange,
                          onChanged: (value) =>
                              Provider.of<ThemeProvider>(context, listen: false)
                                  .toggleTheme(),
                        )
                      ],
                    ),
                  ),

                  // Privacy setting
                  Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary,
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.only(left: 25, top: 10, right: 25),
                    padding: const EdgeInsets.only(
                        left: 25, right: 25, top: 20, bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('Public Account'),
                                const SizedBox(width: 8),
                                Text(
                                  isPublic ? '(Public)' : '(Private)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isPublic ? Colors.green : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Anyone can see your posts and follow you',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        CupertinoSwitch(
                          value: isPublic,
                          activeTrackColor: Colors.orange,
                          onChanged: (value) async {
                            final shouldChange = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Change Privacy?'),
                                content: Text(value
                                    ? 'Are you sure you want to make your account public? Anyone will be able to see your posts and follow you without approval.'
                                    : 'Are you sure you want to make your account private? Users will have to request to follow you and only followers can see your posts.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: Text('Confirm', style: TextStyle(color: Colors.orange)),
                                  ),
                                ],
                              ),
                            );

                            if (shouldChange == true) {
                              await UserService().togglePrivacy(value);
                            }
                          },
                        )
                      ],
                    ),
                  ),

                  // 2FA setting
                  Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary,
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.only(left: 25, top: 10, right: 25),
                    padding: const EdgeInsets.only(
                        left: 25, right: 25, top: 20, bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('Two-Factor Auth (2FA)'),
                                const SizedBox(width: 8),
                                Text(
                                  is2faEnabled ? '(Enabled)' : '(Disabled)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: is2faEnabled ? Colors.green : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Secure your account with an email code',
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ],
                        ),
                        CupertinoSwitch(
                          value: is2faEnabled,
                          activeTrackColor: Colors.orange,
                          onChanged: (value) async {
                            final shouldChange = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Two-Factor Auth'),
                                content: Text(value
                                    ? 'Are you sure you want to enable Two-Factor Authentication? You will receive a verification code on your email every time you log in.'
                                    : 'Are you sure you want to disable Two-Factor Authentication? Your account will be less secure.'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: Text('Confirm', style: TextStyle(color: Colors.orange)),
                                  ),
                                ],
                              ),
                            );

                            if (shouldChange == true) {
                              await UserService().toggleTwoFactor(value);
                            }
                          },
                        )
                      ],
                    ),
                  ),

                  // Notifications
                  Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary,
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.only(left: 25, top: 10, right: 25),
                    padding: const EdgeInsets.only(
                        left: 25, right: 25, top: 20, bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.notifications_outlined, size: 20, color: Colors.orange),
                            const SizedBox(width: 12),
                            const Text('Notifications'),
                          ],
                        ),
                        IconButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const NotificationSettingsPage(),
                              ),
                            );
                          },
                          icon: Icon(
                            Icons.arrow_forward_rounded,
                            color: Theme.of(context).colorScheme.inversePrimary,
                          ),
                        )
                      ],
                    ),
                  ),

                  //blocked users
                  Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary,
                        borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.only(left: 25, top: 10, right: 25),
                    padding: const EdgeInsets.only(
                        left: 25, right: 25, top: 20, bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Blocked users'),
                        IconButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => BlockedUsersPage(),
                              ),
                            );
                          },
                          icon: Icon(
                            Icons.arrow_forward_rounded,
                            color: Theme.of(context).colorScheme.inversePrimary,
                          ),
                        )
                      ],
                    ),
                  ),
                ],
              );
            }
          ),
        ),
      ),
    );
  }
}
