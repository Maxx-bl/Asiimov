import 'package:asiimov/pages/chat_page.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/pages/post_detail_page.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/services/auth/auth_gate.dart';
import 'package:asiimov/pages/follow_requests_page.dart';
import 'package:asiimov/services/notifications/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:asiimov/firebase_options.dart';
import 'package:asiimov/themes/theme_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
/// Global navigator key for navigating from notification taps
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  try {
    await dotenv.load(fileName: "assets/env");
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // Register background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Initialize notification service
    final notificationService = NotificationService();
    await notificationService.initialize();

    // Set up notification tap handler to navigate to correct page
    notificationService.onNotificationTap = (data) async {
      final type = data['type'];
      
      // Wait for navigator to be ready (especially for terminated state start)
      int retryCount = 0;
      while (navigatorKey.currentContext == null && retryCount < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        retryCount++;
      }
      
      final context = navigatorKey.currentContext;
      if (context == null) return;

      debugPrint('Notification Tap Data: $data');

      if (type == 'chat_message') {
        final bool isGroup = data['isGroup'] == 'true';
        if (isGroup) {
          final groupId = data['groupId'];
          final groupName = data['groupName'] ?? 'Group';
          final creatorId = data['creatorId'];
          
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => ChatPage(
                receiverUsername: groupName,
                receiverID: groupId,
                isGroup: true,
                creatorId: creatorId,
              ),
            ),
          );
        } else {
          final senderID = data['senderID'];
          final senderUsername = data['senderUsername'] ?? '';
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (context) => ChatPage(
                receiverUsername: senderUsername,
                receiverID: senderID,
                isGroup: false,
              ),
            ),
          );
        }
      } else if (type == 'follow' || type == 'follow_accept') {
        final senderID = data['senderID'];
        final senderUsername = data['senderUsername'] ?? '';
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => ProfilePage(
              userId: senderID,
              username: senderUsername,
            ),
          ),
        );
      } else if (type == 'follow_request') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (context) => const FollowRequestsPage(),
          ),
        );
      } else if (type == 'comment') {
        final parentPath = data['parentPath'];
        final legacyPostId = data['postId'];
        
        final String? docPath = parentPath ?? (legacyPostId != null ? 'posts/$legacyPostId' : null);

        if (docPath != null) {
          // Fetch the post/comment first to pass it to PostDetailPage
          final doc = await FirebaseFirestore.instance.doc(docPath).get();
          if (doc.exists) {
            final post = Post.fromFirestore(doc);
            navigatorKey.currentState?.push(
              MaterialPageRoute(
                builder: (context) => PostDetailPage(post: post, docPath: docPath),
              ),
            );
          }
        }
      }
    };

    runApp(
      ChangeNotifierProvider(
        create: (context) => ThemeProvider(),
        child: EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('fr')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          child: const MyApp(),
        ),
      ),
    );
  } catch (e, stackTrace) {
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Initialization Error:\n$e\n\n$stackTrace',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
      theme: Provider.of<ThemeProvider>(context).themeData,
    );
  }
}

