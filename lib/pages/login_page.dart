import 'package:asiimov/components/asiimov_mono_logo.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/components/my_button.dart';
import 'package:asiimov/components/my_textfield.dart';
import 'package:asiimov/pages/forgot_password_page.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class LoginPage extends StatefulWidget {
  final void Function()? onTap;

  const LoginPage({super.key, required this.onTap});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void login(BuildContext context) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    final authServices = AuthService();

    try {
      await authServices.signInWithEmailAndPassword(
          emailController.text.trim(), passwordController.text);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("login_success".tr())),
      );
    } catch (e) {
      final error = e.toString().replaceFirst('Exception: ', '');

      String message;
      bool delayBeforeShow = false;
      switch (error) {
        case 'user-not-found':
          message = 'No user found for that email.';
          delayBeforeShow = true;
          break;
        case 'invalid-email':
          message = 'Invalid email address.';
          delayBeforeShow = true;
          break;
        case 'wrong-password':
          message = 'Incorrect password.';
          break;
        default:
          message = 'Login failed.';
      }

      if (delayBeforeShow) {
        await Future.delayed(const Duration(seconds: 1));
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
            child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              //logo
              const AsiimovMonoLogo(),

              const SizedBox(height: 50),

              //text
              Text("login".tr(),
                  style: TextStyle(
                      fontSize: 24,
                      color: Theme.of(context).colorScheme.primary)),

              const SizedBox(height: 50),

              //email field
              MyTextField(
                  hintText: "email".tr(),
                  obscureText: false,
                  controller: emailController),

              const SizedBox(height: 50),

              //password field
              MyTextField(
                  hintText: "password".tr(),
                  obscureText: true,
                  canToggleVisibility: true,
                  controller: passwordController),

              const SizedBox(height: 50),

              //login button
              MyButton(
                text: "go".tr(),
                onTap: () => login(context),
                isLoading: _isLoading,
              ),

              const SizedBox(height: 50),

              //register text
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  "no_account".tr(),
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
                GestureDetector(
                  onTap: widget.onTap,
                  child: Text("register_now".tr(),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary)),
                )
              ]),

              const SizedBox(height: 24),

              // forgot password text
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ForgotPasswordPage(),
                    ),
                  );
                },
                child: Text(
                  "forgot_password".tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        )));
  }
}
