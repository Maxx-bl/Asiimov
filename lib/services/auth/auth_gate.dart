import 'package:asiimov/services/auth/login_or_register.dart';
import 'package:asiimov/pages/main_scaffold.dart';
import 'package:asiimov/pages/verify_email_page.dart';
import 'package:asiimov/pages/two_factor_verification_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              //if logged in
              if (snapshot.hasData) {
                final user = snapshot.data!;
                if (!user.emailVerified) {
                  return const VerifyEmailPage();
                }
                
                // Listen reactively to A2F validation status changes
                return ValueListenableBuilder<bool>(
                  valueListenable: AuthService.isTwoFactorVerifiedNotifier,
                  builder: (context, isVerified, child) {
                    return StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
                      builder: (context, userSnapshot) {
                        if (userSnapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        
                        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                        final is2faEnabled = userData?['two_factor_enabled'] ?? false;
                        
                        if (is2faEnabled && !isVerified) {
                          return const TwoFactorVerificationPage();
                        }
                        
                        return const MainScaffold();
                      }
                    );
                  }
                );
              }
              //if not logged in
              else {
                return const LoginOrRegister();
              }
            }));
  }
}
