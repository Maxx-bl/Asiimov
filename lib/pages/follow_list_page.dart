import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:flutter/material.dart';

class FollowListPage extends StatefulWidget {
  final String userId;
  final String title;
  final bool isFollowers;

  const FollowListPage({
    super.key,
    required this.userId,
    required this.title,
    required this.isFollowers,
  });

  @override
  State<FollowListPage> createState() => _FollowListPageState();
}

class _FollowListPageState extends State<FollowListPage> {
  final userService = UserService();
  final currentUserId = AuthService().getCurrentUser()!.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: widget.isFollowers
            ? userService.getFollowers(widget.userId)
            : userService.getFollowing(widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading list.'));
          }

          final users = snapshot.data ?? [];

          if (users.isEmpty) {
            return Center(
              child: Text(
                widget.isFollowers ? 'No followers yet.' : 'Not following anyone.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 16,
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final username = user['username'] ?? 'Unknown';
              final uid = user['uid'] ?? '';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.withValues(alpha: 0.2),
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
                trailing: (widget.isFollowers && widget.userId == currentUserId)
                    ? IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Remove Follower'),
                              content: Text('Are you sure you want to remove @$username from your followers?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    Navigator.pop(context);
                                    await userService.removeFollower(uid);
                                    setState(() {}); // Refresh list
                                  },
                                  child: const Text('Remove', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
