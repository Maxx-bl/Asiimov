import 'package:asiimov/components/my_button.dart';
import 'package:asiimov/components/my_textfield.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  //text controllers
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  LoginPage({super.key});

  //login
  void login() {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
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
                    fontSize: 16,
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
              onTap: login,
            ),

            const SizedBox(height: 50),

            //register text
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(
                "Don't have an account? ",
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              Text("Register now!",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary))
            ])
          ],
        )));
  }
}
