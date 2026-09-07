import 'package:asiimov/services/auth/login_or_register.dart';
import 'package:asiimov/pages/main_scaffold.dart';
import 'package:asiimov/pages/verify_email_page.dart';
import 'package:asiimov/pages/two_factor_verification_page.dart';
import 'package:asiimov/pages/suspended_account_page.dart';
import 'package:asiimov/pages/user_warning_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/encryption/conversation_key_service.dart';
import 'package:asiimov/services/encryption/user_key_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Cached per-uid so the StreamBuilder below doesn't get a brand new Stream
  // (and thus a spurious ConnectionState.waiting) on every unrelated rebuild
  // of this widget — that used to unmount MainScaffold and reset its tab.
  String? _cachedUid;
  Stream<DocumentSnapshot>? _cachedUserDocStream;

  Stream<DocumentSnapshot> _userDocStream(String uid) {
    if (_cachedUid != uid) {
      _cachedUid = uid;
      _cachedUserDocStream =
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    }
    return _cachedUserDocStream!;
  }

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
                // Initialize E2EE keys for this user (idempotent — fast no-op if already done)
                UserKeyService.initUserKeys();

                // Listen reactively to A2F validation status changes
                return ValueListenableBuilder<bool>(
                  valueListenable: AuthService.isTwoFactorVerifiedNotifier,
                  builder: (context, isVerified, child) {
                    return StreamBuilder<DocumentSnapshot>(
                      stream: _userDocStream(user.uid),
                      builder: (context, userSnapshot) {
                        if (userSnapshot.connectionState == ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator());
                        }
                        
                        final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
                        final isSuspended = userData?['isSuspended'] == true;
                        final suspensionReason = userData?['suspensionReason'] as String? ?? 'no_reason_provided'.tr();
                        
                        if (isSuspended) {
                          return SuspendedAccountPage(reason: suspensionReason);
                        }

                        final activeWarning = userData?['activeWarning'] as Map<String, dynamic>?;
                        if (activeWarning != null) {
                          return UserWarningPage(warningData: activeWarning);
                        }

                        final is2faEnabled = userData?['two_factor_enabled'] ?? false;
                        
                        if (is2faEnabled && AuthService.isNewLoginFlow && !isVerified) {
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
                // Clear all E2EE state on logout
                ConversationKeyService.clearAll();
                UserKeyService.resetForLogout();
                return const LoginOrRegister();
              }
            }));
  }
}
