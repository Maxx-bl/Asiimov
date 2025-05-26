import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/components/my_button.dart';
import 'package:asiimov/components/my_textfield.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  //text controllers
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final void Function()? onTap;

  LoginPage({super.key, required this.onTap});

  //login
  void login(BuildContext context) async {
    final authServices = AuthService();

    try {
      await authServices.signInWithEmailAndPassword(
          emailController.text.trim(), passwordController.text);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Login successful!")),
      );
    } catch (e) {
      final error = e.toString().replaceFirst('Exception: ', '');

      String message;
      switch (error) {
        case 'user-not-found':
          message = 'No user found for that email.';
          break;
        case 'wrong-password':
          message = 'Incorrect password.';
          break;
        case 'invalid-email':
          message = 'Invalid email address.';
          break;
        default:
          message = 'Login failed.';
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
              Text("Login",
                  style: TextStyle(
                      fontSize: 24,
                      color: Theme.of(context).colorScheme.primary)),

              const SizedBox(height: 50),

              //email field
              MyTextField(
                  hintText: "Email",
                  obscureText: false,
                  controller: emailController),

              const SizedBox(height: 50),

              //password field
              MyTextField(
                  hintText: "Password",
                  obscureText: true,
                  controller: passwordController),

              const SizedBox(height: 50),

              //login button
              MyButton(
                text: "Go!",
                onTap: () => login(context),
              ),

              const SizedBox(height: 50),

              //register text
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(
                  "Don't have an account? ",
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.primary),
                ),
                GestureDetector(
                  onTap: onTap,
                  child: Text("Register now!",
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
