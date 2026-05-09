import 'package:asiimov/pages/chat_page.dart';
import 'package:asiimov/services/auth/auth_gate.dart';
import 'package:asiimov/services/notifications/notification_service.dart';
import 'package:asiimov/firebase_options.dart';
import 'package:asiimov/themes/theme_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

/// Global navigator key for navigating from notification taps
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Register background message handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize notification service
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Set up notification tap handler to navigate to chat
  notificationService.onNotificationTap = (senderID, senderUsername) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => ChatPage(
          receiverUsername: senderUsername,
          receiverID: senderID,
        ),
      ),
    );
  };

  runApp(ChangeNotifierProvider(
    create: (context) => ThemeProvider(),
    child: const MyApp(),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
      theme: Provider.of<ThemeProvider>(context).themeData,
    );
  }
}
