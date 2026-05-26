import 'package:asiimov/components/asiimov_mono_logo.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/components/my_button.dart';
import 'package:asiimov/components/my_textfield.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class RegisterPage extends StatefulWidget {
  final void Function()? onTap;

  const RegisterPage({super.key, required this.onTap});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    usernameController.dispose();
    super.dispose();
  }

  bool passwordSize() {
    bool isValid = true;
    if (passwordController.text.length < 6) {
      isValid = false; // Password too short
    }
    return isValid;
  }

  bool passwordsMatch() {
    bool isValid = true;
    if (passwordController.text != confirmController.text) {
      isValid = false; // Passwords do not match
    }
    return isValid;
  }

  bool isValidUsername() {
    final regex = RegExp(r'^[a-z0-9._-]{3,20}$');
    return regex.hasMatch(usernameController.text);
  }

  //register
  void register(BuildContext context) async {
    // Prevent multiple simultaneous registration attempts
    if (_isLoading) return;

    final auth = AuthService();

    String email = emailController.text.trim();
    String password = passwordController.text;
    String confirm = confirmController.text;
    String username = usernameController.text.trim();

    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('passwords_do_not_match'.tr())),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('password_too_short'.tr())),
      );
      return;
    }

    if (!isValidUsername()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'invalid_username_format'.tr())),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await auth.signUpWithEmailAndPassword(email, password, username);
    } catch (e) {
      final error = e.toString().replaceFirst('Exception: ', '');

      String message;
      switch (error) {
        case 'email-already-in-use':
          message = 'This email is already in use.';
          break;
        case 'username-already-in-use':
          message = 'This username is already taken.';
          break;
        default:
          message = 'Registration failed: $error';
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
              Text("sign_up".tr(),
                  style: TextStyle(
                      fontSize: 24,
                      color: Theme.of(context).colorScheme.primary)),

              const SizedBox(height: 50),

              //email field
              MyTextField(
                  hintText: "email".tr(),
                  obscureText: false,
                  controller: emailController),

              const SizedBox(height: 20),

              //password field
              MyTextField(
                  hintText: "password".tr(),
                  obscureText: true,
                  canToggleVisibility: true,
                  controller: passwordController),

              const SizedBox(height: 20),

              //confirm password field
              MyTextField(
                  hintText: "confirm_password".tr(),
                  obscureText: true,
                  canToggleVisibility: true,
                  controller: confirmController),

              const SizedBox(height: 20),

              MyTextField(
                  hintText: "username".tr(),
                  obscureText: false,
                  controller: usernameController),

              const SizedBox(height: 50),

              //login button
              MyButton(
                text: "register".tr(),
                onTap: _isLoading ? null : () => register(context),
              ),

              const SizedBox(height: 50),

              //register text
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  "already_have_account".tr(),
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
                GestureDetector(
                  onTap: widget.onTap,
                  child: Text("login_now".tr(),
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary)),
                )
              ])
            ],
          ),
        )));
  }
}

