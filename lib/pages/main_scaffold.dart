import 'package:asiimov/pages/feed_page.dart';
import 'package:asiimov/pages/home_page.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // Ensure FCM token is updated in Firestore
    AuthService().saveUserToken();

    final currentUser = AuthService().getCurrentUser();
    _pages = [
      const FeedPage(),
      const HomePage(),
      ProfilePage(
        userId: currentUser?.uid ?? '',
        username: currentUser?.displayName ?? 'User',
      ),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        children: _pages,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24.0, 4.0, 24.0, 16.0),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildNavItem(0, Icons.home_outlined, Icons.home, 'feed'.tr()),
                _buildNavItem(1, Icons.chat_bubble_outline, Icons.chat_bubble, 'messages'.tr()),
                _buildNavItem(2, Icons.person_outline, Icons.person, 'profile'.tr()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData unselectedIcon, IconData selectedIcon, String label) {
    final isSelected = _currentIndex == index;
    final primaryColor = Theme.of(context).primaryColor;
    final unselectedColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.5);

    return GestureDetector(
      onTap: () {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryColor.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSelected ? selectedIcon : unselectedIcon,
                  color: isSelected ? primaryColor : unselectedColor,
                  size: 24,
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: SizedBox(
                    width: isSelected ? 8 : 0,
                    height: 0,
                  ),
                ),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    color: isSelected ? primaryColor : unselectedColor,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: isSelected ? 13 : 0,
                  ),
                  child: isSelected ? Text(label) : Text(''),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
