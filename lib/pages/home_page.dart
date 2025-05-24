import 'package:asiimov/components/my_drawer.dart';
import 'package:asiimov/components/user_tile.dart';
import 'package:asiimov/pages/chat_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  HomePage({super.key});

  final ChatService chatService = ChatService();
  final AuthService authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Home"),
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      drawer: const MyDrawer(),
      body: buildUserList(),
    );
  }

  Widget buildUserList() {
    return StreamBuilder(
      stream: chatService.getUsersStream(),
      builder: (context, snapshot) {
        //errors
        if (snapshot.hasError) {
          return const Text("Error");
        }

        //loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        //return list view
        return ListView(
          children: snapshot.data!
              .map<Widget>((userData) => buildUserListItem(userData, context))
              .toList(),
        );
      },
    );
  }

  Widget buildUserListItem(
      Map<String, dynamic> userData, BuildContext context) {
    if (userData['email'] != authService.getCurrentUser()!.email) {
      return UserTile(
          text: userData['email'],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => ChatPage(
                        receiverEmail: userData['email'],
                        receiverID: userData['uid'],
                      )),
            );
          }); // Skip current user
    } else {
      return Container();
    }
  }
}
