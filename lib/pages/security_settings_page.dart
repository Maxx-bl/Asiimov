import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';

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

  bool _isDeletingAccount = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

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
    _emailController.dispose();
    _passwordController.dispose();
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
          SnackBar(
            content: Text('password_reset_email_sent_chec'.tr()),
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

  Future<void> _showDeleteAccountConfirmation() async {
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('delete_account'.tr()),
        content: Text('delete_account_warning'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'continue_action'.tr(), 
              style: const TextStyle(color: Colors.redAccent)
            ),
          ),
        ],
      ),
    );

    if (shouldProceed == true && mounted) {
      _showReauthenticationDialog();
    }
  }

  Future<void> _showReauthenticationDialog() async {
    _emailController.clear();
    _passwordController.clear();
    bool isLoading = false;
    bool obscurePassword = true;
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('reauthenticate_title'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('reauthenticate_desc'.tr()),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'email'.tr(),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'password'.tr(),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword ? Icons.visibility : Icons.visibility_off,
                        color: Theme.of(context).primaryColor,
                      ),
                      onPressed: () {
                        setState(() {
                          obscurePassword = !obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: obscurePassword,
                  enabled: !isLoading,
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: isLoading ? null : () => Navigator.pop(context, false),
                child: Text('cancel'.tr()),
              ),
              ElevatedButton(
                onPressed: isLoading ? null : () async {
                  final email = _emailController.text.trim();
                  final password = _passwordController.text;

                  if (email.isEmpty || password.isEmpty) {
                    setState(() {
                      errorText = 'Please enter both email and password';
                    });
                    return;
                  }

                  if (email.toLowerCase() != _auth.currentUser?.email?.toLowerCase()) {
                    setState(() {
                      errorText = 'Email does not match your account';
                    });
                    return;
                  }

                  setState(() {
                    isLoading = true;
                    errorText = null;
                  });

                  try {
                    final credential = EmailAuthProvider.credential(email: email, password: password);
                    await _auth.currentUser!.reauthenticateWithCredential(credential);
                    if (context.mounted) {
                      Navigator.pop(context, true);
                    }
                  } on FirebaseAuthException catch (e) {
                    setState(() {
                      isLoading = false;
                      errorText = e.message ?? 'Authentication failed';
                    });
                  } catch (e) {
                    setState(() {
                      isLoading = false;
                      errorText = 'An error occurred';
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: isLoading 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('confirm'.tr()),
              ),
            ],
          );
        }
      ),
    );

    if (result == true && mounted) {
      _showFinalConfirmation();
    }
  }

  Future<void> _showFinalConfirmation() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('delete_account'.tr(), style: const TextStyle(color: Colors.redAccent)),
        content: Text('final_delete_confirmation'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'delete_account'.tr(), 
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)
            ),
          ),
        ],
      ),
    );

    if (shouldDelete == true && mounted) {
      _executeDeletion();
    }
  }

  Future<void> _executeDeletion() async {
    setState(() {
      _isDeletingAccount = true;
    });

    try {
      await UserService().deleteUserAccount();
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
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
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingAccount = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('security'.tr()),
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
              ? Center(child: Text('user_not_logged_in'.tr()))
              : StreamBuilder<DocumentSnapshot>(
                  stream: _userStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
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
                                              is2faEnabled ? 'label_enabled'.tr() : 'label_disabled'.tr(),
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
                                          title: Text('twofactor_auth'.tr()),
                                          content: Text(value
                                              ? 'Are you sure you want to enable Two-Factor Authentication? You will receive a verification code on your email every time you log in.'
                                              : 'Are you sure you want to disable Two-Factor Authentication? Your account will be less secure.'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: Text('cancel'.tr()),
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
                                        'change_password'.tr(),
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
                                            : 'send_password_reset_link'.tr(),
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

                              const SizedBox(height: 40),

                              // Delete Account Container
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.redAccent.withValues(alpha: 0.2),
                                  ),
                                ),
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.delete_forever_rounded,
                                          color: Colors.redAccent,
                                          size: 28,
                                        ),
                                        const SizedBox(width: 16),
                                        Text(
                                          'delete_account'.tr(),
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'delete_account_desc'.tr(),
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
                                        onPressed: _isDeletingAccount ? null : _showDeleteAccountConfirmation,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.redAccent,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor: Colors.redAccent.withValues(alpha: 0.3),
                                          disabledForegroundColor: Colors.white.withValues(alpha: 0.5),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          elevation: 0,
                                        ),
                                        child: _isDeletingAccount 
                                            ? const SizedBox(
                                                height: 20, 
                                                width: 20, 
                                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                                              )
                                            : Text(
                                                'delete_account'.tr(),
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
