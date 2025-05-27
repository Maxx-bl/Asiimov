import 'dart:async';

import 'package:asiimov/components/my_drawer.dart';
import 'package:asiimov/components/user_tile.dart';
import 'package:asiimov/pages/chat_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ChatService chatService = ChatService();
  final AuthService authService = AuthService();

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';
  Timer? _debounce;

  // Un key pour forcer le rebuild de StreamBuilder si besoin (optionnel)
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _startSearch() {
    setState(() => _isSearching = true);
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  Future<void> _refreshList() async {
    // Ici tu peux faire des actions pour forcer le refresh,
    // par exemple récupérer les derniers utilisateurs ou messages,
    // mais comme tu utilises un Stream, Firestore se met à jour automatiquement.
    // On simule un délai de 1 seconde pour l'effet refresh.
    await Future.delayed(const Duration(seconds: 1));
    // Forcer rebuild si besoin
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = authService.getCurrentUser();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search user...',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    setState(() {
                      _searchQuery = value.trim().toLowerCase();
                    });
                  });
                },
              )
            : Text(currentUser?.displayName != null
                ? '@${currentUser!.displayName}'
                : 'Home'),
        foregroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          _isSearching
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _stopSearch,
                )
              : IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _startSearch,
                ),
        ],
      ),
      drawer: const MyDrawer(),
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        onRefresh: _refreshList,
        child: buildUserList(),
      ),
    );
  }

  Widget buildUserList() {
    final Stream<List<Map<String, dynamic>>> usersStream = _isSearching
        ? chatService.getUsersStreamExcludingBlocked()
        : chatService.getContactsStreamExcludingBlocked();

    final Stream<Map<String, bool>> unreadStream =
        chatService.getUnreadStatusForContacts();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: usersStream,
      builder: (context, snapshotUsers) {
        if (snapshotUsers.hasError) {
          return const Center(child: Text("Error loading."));
        }
        if (snapshotUsers.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = snapshotUsers.data!
            .where((userData) =>
                userData['email'] != authService.getCurrentUser()!.email &&
                (_searchQuery.isEmpty ||
                    userData['username']
                        .toString()
                        .toLowerCase()
                        .contains(_searchQuery)))
            .toList();

        if (users.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.search_off, size: 48, color: Colors.grey),
                const SizedBox(height: 8),
                Text(
                  _searchQuery.isEmpty
                      ? "No contact available."
                      : "No user found for \"$_searchQuery\"",
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return StreamBuilder<Map<String, bool>>(
          stream: unreadStream,
          builder: (context, snapshotUnread) {
            final unreadStatus = snapshotUnread.data ?? {};

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: users
                  .map((userData) => buildUserListItem(
                      userData, unreadStatus[userData['uid']] ?? false))
                  .toList(),
            );
          },
        );
      },
    );
  }

  Widget buildUserListItem(Map<String, dynamic> userData, bool hasUnread) {
    return UserTile(
      text: userData['username'],
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              receiverUsername: userData['username'],
              receiverID: userData['uid'],
            ),
          ),
        );
      },
      trailing: hasUnread
          ? Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              child: const Text(
                '!',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            )
          : null,
    );
  }
}
