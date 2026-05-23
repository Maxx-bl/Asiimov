import 'package:asiimov/components/user_tile.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

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
              title: Text('unblock_user'.tr()),
              content:
                  Text('are_you_sure_you_want_to_unblo'.tr()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('cancel'.tr()),
                ),
                TextButton(
                  onPressed: () {
                    chatService.unblockUser(userId);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('user_unblocked'.tr()),
                    ));
                  },
                  child: Text('confirm'.tr()),
                )
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final userId = authService.getCurrentUser()!.uid;

    return Scaffold(
        appBar: AppBar(
          title: Text('blocked_users'.tr()),
          foregroundColor: Theme.of(context).colorScheme.primary,
        ),
        body: StreamBuilder<List<Map<String, dynamic>>>(
            stream: chatService.getBlockedUsersStream(userId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Text('error_loading'.tr()),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(child: CircularProgressIndicator());
              }

              final blockedUsers = snapshot.data ?? [];

              if (blockedUsers.isEmpty) {
                return Center(
                  child: Text('no_blocked_users'.tr()),
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
