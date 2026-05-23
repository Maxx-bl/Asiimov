import 'dart:async';
import 'package:asiimov/components/asiimov_mono_logo.dart';
import 'package:asiimov/pages/main_scaffold.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  bool isEmailVerified = false;
  Timer? timer;
  bool canResendEmail = false;
  int countdown = 60;
  Timer? countdownTimer;

  @override
  void initState() {
    super.initState();
    isEmailVerified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;

    if (!isEmailVerified) {
      // Start a timer to check if email is verified
      timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => checkEmailVerified(),
      );
      // Send initial email automatically
      _sendInitialVerificationEmail();
    }
  }

  Future<void> _sendInitialVerificationEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.sendEmailVerification();
        startCooldown();
      }
    } catch (e) {
      debugPrint("Error sending initial verification email: $e");
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> checkEmailVerified() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await user.reload(); // Refresh the user's state
      if (mounted) {
        setState(() {
          isEmailVerified = user.emailVerified;
        });
      }
      
      if (isEmailVerified) {
        timer?.cancel();
        // Return to AuthGate or MainScaffold
      }
    }
  }

  void startCooldown() {
    setState(() {
      canResendEmail = false;
      countdown = 60;
    });

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (countdown > 0) {
            countdown--;
          } else {
            canResendEmail = true;
            timer.cancel();
          }
        });
      }
    });
  }

  Future<void> resendVerificationEmail() async {
    if (!canResendEmail) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.sendEmailVerification();
        startCooldown();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('verification_email_resent'.tr())),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isEmailVerified) {
      return const MainScaffold();
    }

    final email = FirebaseAuth.instance.currentUser?.email ?? 'your email';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('verify_email'.tr()),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const AsiimovMonoLogo(),
              const SizedBox(height: 32),
              Text(
                'Check your inbox',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                  ),
                  children: [
                    TextSpan(text: 'We\'ve sent a verification link to\n'),
                    TextSpan(
                      text: email,
                      style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                    ),
                    TextSpan(text: 'nnplease_click_the_link_to_act'.tr().tr()),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // High priority spam warning container
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.redAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'IMPORTANT:\nIf you do not see the email, please check your SPAM / JUNK folder! Firebase verification emails often land there.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.redAccent.shade100
                              : Colors.redAccent.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              
              // Resend Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: canResendEmail ? resendVerificationEmail : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade400,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: canResendEmail ? 2 : 0,
                  ),
                  child: Text(
                    canResendEmail ? 'Resend Email' : 'Resend Email in ${countdown}s',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Cancel / Sign out
              TextButton(
                onPressed: () {
                  AuthService().signOut();
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                ),
                child: Text(
                  'Cancel & Sign Out',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
