import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Stream<DocumentSnapshot>? _userStream;

  // Static expiration time to persist across page destruction
  static DateTime? _cooldownExpiration;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) {
      // Initialize stream ONCE to prevent rebuild loops/flashing when setState is called
      _userStream = UserService().getUserStream(user.uid);
    }

    // Resume cooldown if active
    if (_cooldownExpiration != null) {
      final difference = _cooldownExpiration!.difference(DateTime.now()).inSeconds;
      if (difference > 0) {
        _cooldown = difference;
        _startTimer();
      }
    }
  }

  @override
  void dispose() {
    // Cancel the timer to prevent memory leaks and setState calls on disposed widget
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_cooldown > 0) {
            _cooldown--;
          } else {
            timer.cancel();
          }
        });
      } else {
        if (_cooldown > 0) {
          _cooldown--;
        } else {
          timer.cancel();
        }
      }
    });
  }

  void _startCooldown() {
    _cooldownExpiration = DateTime.now().add(const Duration(seconds: 60));
    setState(() {
      _cooldown = 60;
    });
    _startTimer();
  }

  Future<void> _sendPasswordReset() async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;

    try {
      await _auth.sendPasswordResetEmail(email: user.email!);
      _startCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset email sent! Check your SPAM folder.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Security'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: user == null || _userStream == null
              ? const Center(child: Text('User not logged in'))
              : StreamBuilder<DocumentSnapshot>(
                  stream: _userStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final userData = snapshot.data?.data() as Map<String, dynamic>?;
                    final is2faEnabled = userData?['two_factor_enabled'] ?? false;

                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                        child: Column(
                          children: [
                            // 2FA Container
                            Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondary,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                                ),
                              ),
                              padding: const EdgeInsets.all(20.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.security_rounded,
                                              color: Theme.of(context).primaryColor,
                                              size: 26,
                                            ),
                                            const SizedBox(width: 16),
                                            Text(
                                              'Two-Factor Auth',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(context).colorScheme.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              is2faEnabled ? '(Enabled)' : '(Disabled)',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: is2faEnabled ? Colors.green : Theme.of(context).primaryColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Secure your account with an email code',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  CupertinoSwitch(
                                    value: is2faEnabled,
                                    activeTrackColor: Theme.of(context).primaryColor,
                                    onChanged: (value) async {
                                      final shouldChange = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('Two-Factor Auth'),
                                          content: Text(value
                                              ? 'Are you sure you want to enable Two-Factor Authentication? You will receive a verification code on your email every time you log in.'
                                              : 'Are you sure you want to disable Two-Factor Authentication? Your account will be less secure.'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, true),
                                              child: Text('Confirm', style: TextStyle(color: Theme.of(context).primaryColor)),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (shouldChange == true) {
                                        await UserService().toggleTwoFactor(value);
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Password Reset Container
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondary,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                                ),
                              ),
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.lock_reset_rounded,
                                        color: Theme.of(context).primaryColor,
                                        size: 28,
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        'Change Password',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Send a secure link to ${user.email} to reset your password.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  
                                  // Button
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: _cooldown > 0 ? null : _sendPasswordReset,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context).primaryColor,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                                        disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: Text(
                                        _cooldown > 0
                                            ? 'Send again in ${_cooldown}s'
                                            : 'Send Password Reset Link',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
