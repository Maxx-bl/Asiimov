import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/pages/settings_page.dart';
import 'package:flutter/material.dart';

class MyDrawer extends StatelessWidget {
  const MyDrawer({super.key});

  void logout() {
    final auth = AuthService();
    auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
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

          //home list tile
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: ListTile(
              title: const Text('H O M E'),
              leading: const Icon(Icons.home),
              onTap: () {
                Navigator.pop(context);
              },
            ),
          ),

          //settings list tile
          Padding(
            padding: const EdgeInsets.only(left: 25),
            child: ListTile(
              title: const Text('S E T T I N G S'),
              leading: const Icon(Icons.settings),
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SettingsPage()));
              },
            ),
          ),
        ]),

        //logout list tile
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
