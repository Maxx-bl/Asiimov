import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class VotersListSheet extends StatelessWidget {
  final List<String> userIds;
  final String title;

  const VotersListSheet({
    super.key,
    required this.userIds,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    if (userIds.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No one has $title yet.',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Divider(),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: userIds.length,
              itemBuilder: (context, index) {
                final userId = userIds[index];
                return FutureBuilder<DocumentSnapshot>(
                  future: UserService().getUserProfile(userId),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return ListTile(
                        leading: const CircleAvatar(radius: 16, backgroundColor: Colors.grey),
                        title: Container(
                          height: 12,
                          width: 100,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }

                    final userData = snapshot.data!.data() as Map<String, dynamic>?;
                    final username = userData?['username'] ?? 'Unknown';

                    return ListTile(
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfilePage(
                              userId: userId,
                              username: username,
                            ),
                          ),
                        );
                      },
                      leading: ProfileAvatar(
                        userId: userId,
                        username: username,
                        radius: 16,
                      ),
                      title: UsernameDisplay(
                        userId: userId,
                        username: username,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
