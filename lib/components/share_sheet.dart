import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:flutter/material.dart';

class ShareSheet extends StatefulWidget {
  final Post post;

  const ShareSheet({super.key, required this.post});

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final ChatService _chatService = ChatService();
  final PostService _postService = PostService();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedUserIds = {};
  String _searchQuery = "";

  late Stream<List<Map<String, dynamic>>> _recentChatsStream;
  late Stream<List<Map<String, dynamic>>> _allUsersStream;

  @override
  void initState() {
    super.initState();
    _recentChatsStream = _chatService.getContactsStreamExcludingBlocked();
    _allUsersStream = _chatService.getUsersStream();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleUserSelection(String userId) {
    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
      } else {
        _selectedUserIds.add(userId);
      }
    });
  }

  Future<void> _sendPost() async {
    if (_selectedUserIds.isEmpty) return;

    final List<String> userIds = _selectedUserIds.toList();

    // Close sheet first for better UX
    Navigator.pop(context);

    // Share post
    await _chatService.sharePost(widget.post.id, userIds);

    // Increment share count and record who shared it
    await _postService.incrementShareCount(
        widget.post.id, AuthService().getCurrentUser()!.uid);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Post shared with ${userIds.length} person(s)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Search user...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.secondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value.toLowerCase();
              });
            },
          ),
          const SizedBox(height: 16),

          // User list
          Expanded(
            child: _searchQuery.isEmpty
                ? _buildRecentChatsList()
                : _buildSearchList(),
          ),

          // Send button
          if (_selectedUserIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _sendPost,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text("Send (${_selectedUserIds.length})"),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentChatsList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _recentChatsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return const Center(child: Text("No recent chats"));
        }

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final userId = user['uid'];
            final isSelected = _selectedUserIds.contains(userId);

            return _buildUserTile(user, isSelected);
          },
        );
      },
    );
  }

  Widget _buildSearchList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _allUsersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = (snapshot.data ?? []).where((user) {
          final username = user['username']?.toString().toLowerCase() ?? "";
          return username.contains(_searchQuery);
        }).toList();

        if (users.isEmpty) {
          return const Center(child: Text("No user found"));
        }

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final userId = user['uid'];
            final isSelected = _selectedUserIds.contains(userId);

            return _buildUserTile(user, isSelected);
          },
        );
      },
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user, bool isSelected) {
    final userId = user['uid'];
    final username = user['username'] ?? "Anonymous";

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondary,
        child: Text(username[0].toUpperCase()),
      ),
      title: UsernameDisplay(
        userId: userId,
        username: username,
      ),
      trailing: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color:
                isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
            width: 2,
          ),
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
      onTap: () => _toggleUserSelection(userId),
    );
  }
}
