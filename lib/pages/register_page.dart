import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/components/my_button.dart';
import 'package:asiimov/components/my_textfield.dart';
import 'package:flutter/material.dart';

class RegisterPage extends StatelessWidget {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();

  final void Function()? onTap;

  RegisterPage({super.key, required this.onTap});

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
    final auth = AuthService();

    String email = emailController.text.trim();
    String password = passwordController.text;
    String confirm = confirmController.text;
    String username = usernameController.text.trim();

    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match!')),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Password must be at least 6 characters.')),
      );
      return;
    }

    if (!isValidUsername()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Username must be 3-20 characters, lowercase letters/numbers/._- only.')),
      );
      return;
    }

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
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
              Icon(Icons.message,
                  size: 60, color: Theme.of(context).colorScheme.primary),

              const SizedBox(height: 50),

              //text
              Text("Sign Up",
                  style: TextStyle(
                      fontSize: 24,
                      color: Theme.of(context).colorScheme.primary)),

              const SizedBox(height: 50),

              //email field
              MyTextField(
                  hintText: "Email",
                  obscureText: false,
                  controller: emailController),

              const SizedBox(height: 20),

              //password field
              MyTextField(
                  hintText: "Password",
                  obscureText: true,
                  controller: passwordController),

              const SizedBox(height: 20),

              //confirm password field
              MyTextField(
                  hintText: "Confirm password",
                  obscureText: true,
                  controller: confirmController),

              const SizedBox(height: 20),

              MyTextField(
                  hintText: "Username",
                  obscureText: false,
                  controller: usernameController),

              const SizedBox(height: 50),

              //login button
              MyButton(
                text: "Register",
                onTap: () => register(context),
              ),

              const SizedBox(height: 50),

              //register text
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  "Already have an account? ",
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
                GestureDetector(
                  onTap: onTap,
                  child: Text("Login now!",
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
