import 'package:asiimov/components/user_tile.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:flutter/material.dart';

class BlockedUsersPage extends StatelessWidget {
  BlockedUsersPage({super.key});

  //services
  final ChatService chatService = ChatService();
  final AuthService authService = AuthService();

  //unblock box
  void showUnblockBox(BuildContext context, String userId) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Unblock user'),
              content:
                  const Text('Are you sure you want to unblock this user?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    chatService.unblockUser(userId);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('User unblocked!'),
                    ));
                  },
                  child: const Text('Confirm'),
                )
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final userId = authService.getCurrentUser()!.uid;

    return Scaffold(
        appBar: AppBar(
          title: const Text('Blocked users'),
          foregroundColor: Theme.of(context).colorScheme.primary,
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
            stream: chatService.getBlockedUsersStream(userId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('Error loading...'),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final blockedUsers = snapshot.data ?? [];

              if (blockedUsers.isEmpty) {
                return const Center(
                  child: Text('No blocked users'),
                );
              }

              return ListView.builder(
                  itemCount: blockedUsers.length,
                  itemBuilder: (context, index) {
                    final user = blockedUsers[index];
                    return UserTile(
                        text: user['username'],
                        onTap: () => showUnblockBox(context, user['uid']));
                  });
            }));
  }
}
