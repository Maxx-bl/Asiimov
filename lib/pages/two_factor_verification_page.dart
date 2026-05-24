import 'dart:async';
import 'dart:math';
import 'package:asiimov/components/asiimov_mono_logo.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/components/my_button.dart';
import 'package:asiimov/components/my_textfield.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:asiimov/themes/theme_provider.dart';

class TwoFactorVerificationPage extends StatefulWidget {
  const TwoFactorVerificationPage({super.key});

  @override
  State<TwoFactorVerificationPage> createState() => _TwoFactorVerificationPageState();
}

class _TwoFactorVerificationPageState extends State<TwoFactorVerificationPage> {
  final TextEditingController codeController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  bool canResend = false;
  int countdown = 60;
  Timer? countdownTimer;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    // Automatically generate and send the code on load
    _send2faCode();
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    codeController.dispose();
    super.dispose();
  }

  void startCooldown() {
    setState(() {
      canResend = false;
      countdown = 60;
    });

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (countdown > 0) {
            countdown--;
          } else {
            canResend = true;
            timer.cancel();
          }
        });
      }
    });
  }

  Future<void> _send2faCode() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    try {
      // Generate a 6-digit random code
      final int code = 100000 + Random().nextInt(900000);

      // Print code to standard output for debugging (extremely helpful when Trigger Email is not set up)
      debugPrint("🔑 [DEBUG 2FA] Your verification code is: $code");

      // Store in Firestore securely
      await _firestore.collection('two_factor_codes').doc(user.uid).set({
        'code': code.toString(),
        'email': user.email,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      final dominantColor = themeProvider.dominantColor;
      final hexColor = '#${ThemeProvider.colorToHex(dominantColor)}';
      final rgbaColor = 'rgba(${dominantColor.red}, ${dominantColor.green}, ${dominantColor.blue}, 0.3)';

      // Write to the standard Trigger Email collection ('mail')
      await _firestore.collection('mail').add({
        'to': user.email,
        'from': 'Glyphe <max13.bl@gmail.com>', // Force the sender name to "Glyphe"
        'message': {
          'subject': 'Your Glyphe 2FA Code',
          'text': 'Your two-factor verification code is: $code. It expires in 5 minutes.',
          'html': '<div style="font-family: \'Segoe UI\', Tahoma, Geneva, Verdana, sans-serif; background-color: #0c0f14; padding: 40px 20px; color: #ffffff; text-align: center;"><div style="max-width: 500px; margin: 0 auto; background-color: #171d26; border-radius: 16px; padding: 32px; border: 1.5px solid $hexColor; box-shadow: 0 8px 30px rgba(0,0,0,0.5);"><h2 style="color: $hexColor; margin: 0 0 8px 0; font-size: 28px; letter-spacing: 2px; font-weight: 800;">GLYPHE</h2><p style="color: #a0aec0; font-size: 13px; margin: 0 0 32px 0; letter-spacing: 1px; text-transform: uppercase;">Double Authentication (2FA)</p><div style="background-color: #0c0f14; border-radius: 12px; padding: 24px; margin-bottom: 32px; border: 1px dashed $rgbaColor;"><p style="color: #a0aec0; font-size: 11px; text-transform: uppercase; letter-spacing: 2px; margin: 0 0 12px 0;">Your Verification Code</p><span style="font-size: 40px; font-weight: bold; color: $hexColor; letter-spacing: 8px; font-family: monospace;">$code</span></div><p style="color: #a0aec0; font-size: 13px; line-height: 1.6; margin: 0 0 24px 0;">This code will expire in <strong>5 minutes</strong>.<br>If you did not request this verification, you can safely ignore this email.</p><div style="border-top: 1px solid rgba(255, 255, 255, 0.05); padding-top: 20px; font-size: 11px; color: #718096;">This is an automated security message. Please do not reply directly to this email.</div></div></div>',
        }
      });

      startCooldown();
    } catch (e) {
      debugPrint("Error sending 2FA code: $e");
    }
  }

  Future<void> verifyCode() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final inputCode = codeController.text.trim();
    if (inputCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('please_enter_the_6digit_code'.tr())),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final doc = await _firestore.collection('two_factor_codes').doc(user.uid).get();
      if (!doc.exists) {
        throw Exception('Code not found. Please request a new one.');
      }

      final data = doc.data()!;
      final correctCode = data['code'] as String?;
      final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

      if (correctCode == null || createdAt == null) {
        throw Exception('Invalid verification data. Please try again.');
      }

      // Check for 5 minute expiration
      final isExpired = DateTime.now().difference(createdAt).inMinutes >= 5;
      if (isExpired) {
        throw Exception('The code has expired. Please request a new one.');
      }

      if (inputCode == correctCode) {
        // Mark as verified in memory
        AuthService.isTwoFactorVerified = true;

        // Force a reload of current user to update the UI
        await user.reload();
        
        // This will trigger AuthGate StreamBuilder to reload and let the user in
      } else {
        throw Exception('Incorrect verification code. Please try again.');
      }
    } catch (e) {
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _auth.currentUser?.email ?? 'your email';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('2fa_verification'.tr()),
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
                  'Two-Factor Auth',
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
                      fontSize: 15,
                      height: 1.5,
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                    ),
                    children: [
                      TextSpan(text: 'please_enter_the_6digit_verifi'.tr().tr()),
                      TextSpan(
                        text: email,
                        style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor),
                      ),
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
                          'IMPORTANT:\nIf you do not see the email, please check your SPAM / JUNK folder! 2FA emails often land there.',
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
                
                // Code Input
                MyTextField(
                  hintText: '6digit_code'.tr().tr(),
                  obscureText: false,
                  controller: codeController,
                ),
                
                const SizedBox(height: 32),
                
                // Action Button
                SizedBox(
                  width: double.infinity,
                  child: isLoading
                      ? Center(child: CircularProgressIndicator())
                      : MyButton(
                          text: 'verify'.tr(),
                          onTap: verifyCode,
                        ),
                ),
                
                const SizedBox(height: 16),
                
                // Resend Button
                TextButton(
                  onPressed: canResend ? _send2faCode : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                  ),
                  child: Text(
                    canResend ? 'resend_code'.tr() : 'Resend Code in ${countdown}s',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Cancel / Sign out
                TextButton(
                  onPressed: () {
                    AuthService().signOut();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                  ),
                  child: Text(
                    'cancel_sign_out'.tr(),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
