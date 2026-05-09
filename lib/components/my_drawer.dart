import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/pages/settings_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:flutter/material.dart';

class MyDrawer extends StatelessWidget {
  const MyDrawer({super.key});

  void logout() {
    final auth = AuthService();
    auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = AuthService().getCurrentUser();

    return Drawer(
      backgroundColor: Theme.of(context).colorScheme.surface,
      child:
          Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(children: [
          //logo
          DrawerHeader(
            child: Center(
              child: Icon(Icons.message,
                  color: Theme.of(context).colorScheme.primary, size: 40),
            ),
          ),

          //profile
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: ListTile(
              title: const Text('P R O F I L E'),
              leading: const Icon(Icons.person),
              onTap: () {
                Navigator.pop(context);
                if (currentUser != null) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ProfilePage(
                        userId: currentUser.uid,
                        username: currentUser.displayName ?? 'User',
                      ),
                    ),
                  );
                }
              },
            ),
          ),

          //settings
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: ListTile(
              title: const Text('S E T T I N G S'),
              leading: const Icon(Icons.settings),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsPage(),
                  ),
                );
              },
            ),
          ),
        ]),

        //logout
        Padding(
          padding: const EdgeInsets.only(left: 25, bottom: 25),
          child: ListTile(
            title: const Text('L O G O U T'),
            leading: const Icon(Icons.logout),
            onTap: logout,
          ),
        ),
      ]),
    );
  }
}
