import 'dart:async';
import 'package:asiimov/components/asiimov_mono_logo.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/components/my_button.dart';
import 'package:asiimov/components/my_textfield.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController emailController = TextEditingController();
  bool canSendReset = true;
  int countdown = 60;
  Timer? countdownTimer;

  @override
  void dispose() {
    countdownTimer?.cancel();
    emailController.dispose();
    super.dispose();
  }

  void startCooldown() {
    setState(() {
      canSendReset = false;
      countdown = 60;
    });

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (countdown > 0) {
            countdown--;
          } else {
            canSendReset = true;
            timer.cancel();
          }
        });
      }
    });
  }

  Future<void> sendResetEmail() async {
    final String email = emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('please_enter_your_email_addres'.tr())),
      );
      return;
    }

    try {
      await AuthService().sendPasswordResetEmail(email);
      startCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('password_reset_link_sent_check'.tr()),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      final error = e.toString().replaceFirst('Exception: ', '');
      String message = 'An error occurred. Please try again.';

      if (error == 'user-not-found') {
        message = 'No user found with this email.';
      } else if (error == 'invalid-email') {
        message = 'Invalid email address format.';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('reset_password'.tr()),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const AsiimovMonoLogo(),
                const SizedBox(height: 32),
                Text(
                  'forgot_password_title'.tr(),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Enter your email address below and we will send you a link to reset your password.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
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
                          'IMPORTANT:\nIf you do not see the email, please check your SPAM / JUNK folder! Reset emails often land there.',
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
                const SizedBox(height: 24),
                
                // Email Field
                MyTextField(
                  hintText: 'email'.tr(),
                  obscureText: false,
                  controller: emailController,
                ),
                
                const SizedBox(height: 32),
                
                // Action Button
                SizedBox(
                  width: double.infinity,
                  child: MyButton(
                    text: canSendReset ? 'send_link'.tr() : 'Resend in ${countdown}s',
                    onTap: canSendReset ? sendResetEmail : () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
