import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/pages/settings_page.dart';
import 'package:asiimov/pages/admin_dashboard_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

          //admin panel
          if (currentUser != null)
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasData) {
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  final isAdmin = data?['isAdmin'] == true;

                  if (isAdmin) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 25),
                      child: ListTile(
                        title: const Text('A D M I N   P A N E L'),
                        leading: const Icon(Icons.admin_panel_settings, color: Colors.redAccent),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AdminDashboardPage(),
                            ),
                          );
                        },
                      ),
                    );
                  }
                }
                return const SizedBox.shrink();
              },
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
