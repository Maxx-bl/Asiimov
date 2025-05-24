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
    //auth services
    final authServices = AuthService();

    //try login
    try {
      await authServices.signInWithEmailAndPassword(
          emailController.text, passwordController.text);
    }

    //catch errors
    catch (e) {
      //show error message
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(e.toString()),
        ),
      );
    }
  }

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
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
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
        )));
  }
}
