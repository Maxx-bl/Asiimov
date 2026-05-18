import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  bool _messages = true;
  bool _followers = true;
  bool _comments = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .get();
    final data = doc.data();
    final prefs = data?['notificationPrefs'] as Map<String, dynamic>? ?? {};

    if (mounted) {
      setState(() {
        _messages = prefs['messages'] ?? true;
        _followers = prefs['followers'] ?? true;
        _comments = prefs['comments'] ?? true;
        _isLoading = false;
      });
    }
  }

  Future<void> _updatePref(String key, bool value) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .set({
      'notificationPrefs': {key: value},
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  children: [
                    const SizedBox(height: 10),

                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
                      child: Text(
                        'Choose which notifications you want to receive',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                        ),
                      ),
                    ),

                    // Messages
                    _buildToggleTile(
                      icon: Icons.chat_bubble_outline,
                      title: 'Messages',
                      subtitle: 'Private messages and group chats',
                      value: _messages,
                      onChanged: (value) {
                        setState(() => _messages = value);
                        _updatePref('messages', value);
                      },
                    ),

                    // Followers
                    _buildToggleTile(
                      icon: Icons.person_add_outlined,
                      title: 'Followers',
                      subtitle: 'New followers and follow requests',
                      value: _followers,
                      onChanged: (value) {
                        setState(() => _followers = value);
                        _updatePref('followers', value);
                      },
                    ),

                    // Comments
                    _buildToggleTile(
                      icon: Icons.comment_outlined,
                      title: 'Comments',
                      subtitle: 'Comments on your posts',
                      value: _comments,
                      onChanged: (value) {
                        setState(() => _comments = value);
                        _updatePref('comments', value);
                      },
                    ),

                    const SizedBox(height: 24),

                    // Info
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 25),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.grey.shade500),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You can also mute individual group chats from their settings.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.only(left: 25, top: 10, right: 25),
      padding: const EdgeInsets.only(left: 20, right: 15, top: 12, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).primaryColor),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: Theme.of(context).primaryColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
