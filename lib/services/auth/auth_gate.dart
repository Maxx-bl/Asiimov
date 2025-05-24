import 'package:asiimov/services/auth/login_or_register.dart';
import 'package:asiimov/pages/home_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: StreamBuilder(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              //if logged in
              if (snapshot.hasData) {
                return HomePage();
              }
              //if not logged in
              else {
                return const LoginOrRegister();
              }
            }));
  }
}
