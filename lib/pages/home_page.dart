import 'dart:async';

import 'package:asiimov/components/group_creation_sheet.dart';
import 'package:asiimov/components/group_icon.dart';
import 'package:asiimov/components/user_tile.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/models/conversation.dart';
import 'package:asiimov/pages/chat_page.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  String _searchQuery = "";
  Timer? _debounce;
  final FocusNode _searchFocusNode = FocusNode();

  final ScrollController _searchScrollController = ScrollController();
  int _searchLimit = 20;
  bool _isLoadingMoreSearch = false;

  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey =
      GlobalKey<RefreshIndicatorState>();

  @override
  void initState() {
    super.initState();
    _searchScrollController.addListener(_onSearchScroll);
  }

  void _onSearchScroll() {
    if (_searchScrollController.position.pixels >=
        _searchScrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMoreSearch && _isSearching) {
        setState(() {
          _isLoadingMoreSearch = true;
          _searchLimit += 20;
        });
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) setState(() => _isLoadingMoreSearch = false);
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchScrollController.dispose();
    super.dispose();
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
      _searchLimit = 20;
    });
    Future.microtask(() => _searchFocusNode.requestFocus());
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchQuery = "";
      _searchController.clear();
      _searchLimit = 20;
    });
  }

  void _openGroupCreation() async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const GroupCreationSheet(),
    );

    if (result != null && result is String && mounted) {
      // result is the groupId
      // The conversation stream will pick it up and display it in the list.
    }
  }

  Future<void> _refreshList() async {
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
                focusNode: _searchFocusNode,
                decoration: InputDecoration(
                  hintText: 'Search user...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                ),
                onChanged: (value) {
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    setState(() {
                      _searchQuery = value.trim().toLowerCase();
                      _searchLimit = 20; // Reset limit on new search
                    });
                  });
                },
              )
            : (currentUser?.displayName != null
                ? Builder(builder: (context) {
                    final user = currentUser!;
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfilePage(
                              userId: user.uid,
                              username: user.displayName!,
                            ),
                          ),
                        );
                      },
                      child: UsernameDisplay(
                        userId: user.uid,
                        username: user.displayName!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 20),
                        iconSize: 20,
                      ),
                    );
                  })
                : const Text('Home')),
        foregroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          if (!_isSearching)
            IconButton(
              onPressed: _openGroupCreation,
              icon: const Icon(Icons.add),
            ),
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
      body: RefreshIndicator(
        key: _refreshIndicatorKey,
        onRefresh: _refreshList,
        child: buildUserList(),
      ),
    );
  }

  Widget buildUserList() {
    // If searching, we use a simpler stream that fetches all users
    if (_isSearching) {
      return StreamBuilder<DocumentSnapshot>(
        stream: UserService().getUserStream(authService.getCurrentUser()!.uid),
        builder: (context, userSnapshot) {
          final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
          final following = List<String>.from(userData?['following'] ?? []);

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream:
                chatService.getUsersStreamExcludingBlocked(limit: _searchLimit),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Text("Error"));
              if (snapshot.connectionState == ConnectionState.waiting &&
                  _searchLimit == 20) {
                return const Center(child: CircularProgressIndicator());
              }

              final users = snapshot.data ?? [];
              final filteredUsers = users.where((u) {
                final username = u['username'].toString().toLowerCase();
                final matchesQuery =
                    _searchQuery.isEmpty || username.contains(_searchQuery);
                final isFollowing = following.contains(u['uid']);
                return (_searchQuery.isEmpty ? isFollowing : matchesQuery);
              }).toList();

              if (filteredUsers.isEmpty &&
                  snapshot.connectionState != ConnectionState.waiting) {
                return _buildEmptyState();
              }

              return ListView.builder(
                controller: _searchScrollController,
                itemCount:
                    filteredUsers.length + (_isLoadingMoreSearch ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == filteredUsers.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final u = filteredUsers[index];
                  return UserTile(
                    text: u['username'],
                    userId: u['uid'],
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ProfilePage(
                            userId: u['uid'],
                            username: u['username'],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    }

    // HIGH PERFORMANCE: Main conversation list with optimized single stream
    return StreamBuilder<List<Conversation>>(
      stream: chatService.getConversationsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Error: ${snapshot.error}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final conversations = snapshot.data ?? [];
        if (conversations.isEmpty) return _buildEmptyState();

        return ListView.builder(
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            return buildConversationItem(conversations[index]);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            _isSearching ? "No user found" : "No conversations yet",
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget buildConversationItem(Conversation conv) {
    // Format date
    String dateString = '';
    final DateTime date = conv.lastActive;
    final DateTime now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      dateString =
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      dateString =
          '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
    }

    // Decrypt preview
    String messagePreview = "Start chatting...";
    if (conv.lastMessage != null) {
      try {
        final lastMsg = conv.lastMessage!;
        final rawMsg = lastMsg['message'];

        if (lastMsg['isSystemMessage'] == true) {
          messagePreview = rawMsg;
        } else {
          final decrypted = chatService.encryption.decrypt(rawMsg);
          final senderName =
              lastMsg['senderID'] == authService.getCurrentUser()!.uid
                  ? 'You'
                  : lastMsg['senderUsername'];

          String displayMsg =
              decrypted.isEmpty ? 'Sent an attachment 📎' : decrypted;

          if (conv.isGroup) {
            messagePreview = '$senderName: $displayMsg';
          } else {
            messagePreview =
                lastMsg['senderID'] == authService.getCurrentUser()!.uid
                    ? 'You: $displayMsg'
                    : displayMsg;
          }
        }
      } catch (e) {
        messagePreview = "Encrypted message";
      }
    }

    // Determine status (sent/seen) if I am the sender
    String? status;
    if (conv.lastMessage != null && !conv.isGroup) {
      final isMyMessage =
          conv.lastMessage!['senderID'] == authService.getCurrentUser()!.uid;
      if (isMyMessage) {
        status = conv.lastMessage!['isRead'] == true ? 'seen' : 'sent';
      }
    }

    return UserTile(
      text: conv.otherUsername,
      userId: conv.isGroup ? '' : conv.otherUserId,
      leading: conv.isGroup
          ? GroupIcon(size: 40, imageUrl: conv.groupIconUrl)
          : null,
      subtitle: Text(
        messagePreview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: conv.unreadCount > 0
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
          fontSize: 13,
          fontWeight:
              conv.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 10,
                  color: status == 'seen'
                      ? Theme.of(context).primaryColor
                      : Colors.grey.shade500,
                  fontWeight:
                      status == 'seen' ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          Text(
            dateString,
            style: TextStyle(
              color: conv.unreadCount > 0
                  ? Theme.of(context).primaryColor
                  : Colors.grey,
              fontSize: 11,
              fontWeight:
                  conv.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (conv.unreadCount > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '+${conv.unreadCount}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              receiverUsername: conv.otherUsername,
              receiverID: conv.otherUserId,
              isGroup: conv.isGroup,
              creatorId: conv.creatorId,
            ),
          ),
        );
      },
    );
  }
}
