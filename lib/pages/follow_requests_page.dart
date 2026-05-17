import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FollowRequestsPage extends StatefulWidget {
  const FollowRequestsPage({super.key});

  @override
  State<FollowRequestsPage> createState() => _FollowRequestsPageState();
}

class _FollowRequestsPageState extends State<FollowRequestsPage> {
  final userService = UserService();
  final currentUserId = FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow Requests'),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: StreamBuilder<List<String>>(
        stream: userService.getFollowRequestsStream(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading requests.'));
          }

          final requesterIds = snapshot.data ?? [];

          if (requesterIds.isEmpty) {
            return Center(
              child: Text(
                'No requests yet.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 16,
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: requesterIds.length,
            itemBuilder: (context, index) {
              final uid = requesterIds[index];

              return FutureBuilder<DocumentSnapshot>(
                future: userService.getUserFuture(uid),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const ListTile(title: Text('Loading...'));
                  }

                  final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                  if (userData == null) return const SizedBox.shrink();

                  final username = userData['username'] ?? 'Unknown';

                  return ListTile(
                    leading: ProfileAvatar(
                      userId: uid,
                      username: username,
                      radius: 20,
                    ),
                    title: UsernameDisplay(
                      userId: uid,
                      username: username,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfilePage(
                            userId: uid,
                            username: username,
                          ),
                        ),
                      );
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Decline
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red),
                          onPressed: () async {
                            await userService.declineFollowRequest(uid);
                          },
                        ),
                        // Accept
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.green),
                          onPressed: () async {
                            await userService.acceptFollowRequest(uid);
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
