import 'package:asiimov/components/group_icon.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/models/post.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:flutter/material.dart';

class ShareSheet extends StatefulWidget {
  final Post post;
  final String? docPath;

  const ShareSheet({super.key, required this.post, this.docPath});

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
  late Stream<List<Map<String, dynamic>>> _groupsStream;
  final Set<String> _selectedGroupIds = {};

  @override
  void initState() {
    super.initState();
    _recentChatsStream = _chatService.getContactsStreamExcludingBlocked();
    _allUsersStream = _chatService.getUsersStream();
    _groupsStream = _chatService.getConversationsStream().map((convs) => 
      convs.where((c) => c.isGroup).map((c) => {
        'uid': c.otherUserId,
        'username': c.groupName,
        'isGroup': true,
      }).toList()
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleUserSelection(String id, {bool isGroup = false}) {
    setState(() {
      if (isGroup) {
        if (_selectedGroupIds.contains(id)) {
          _selectedGroupIds.remove(id);
        } else {
          _selectedGroupIds.add(id);
        }
      } else {
        if (_selectedUserIds.contains(id)) {
          _selectedUserIds.remove(id);
        } else {
          _selectedUserIds.add(id);
        }
      }
    });
  }

  Future<void> _sendPost() async {
    if (_selectedUserIds.isEmpty && _selectedGroupIds.isEmpty) return;

    final List<String> userIds = _selectedUserIds.toList();
    final List<String> groupIds = _selectedGroupIds.toList();

    // Close sheet first for better UX
    Navigator.pop(context);

    final String pathToSend = widget.docPath ?? 'posts/${widget.post.id}';

    // Share post to users
    for (String id in userIds) {
      await _chatService.sendMessage(id, "Shared a post", 
        messageType: 'post_share', sharedPostId: pathToSend);
    }

    // Share post to groups
    for (String id in groupIds) {
      await _chatService.sendMessage(id, "Shared a post", 
        isGroup: true, messageType: 'post_share', sharedPostId: pathToSend);
    }

    // Increment share count and record who shared it
    await _postService.incrementShareCount(
        pathToSend, AuthService().getCurrentUser()!.uid);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Post shared with ${userIds.length + groupIds.length} chat(s)')),
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
          if (_selectedUserIds.isNotEmpty || _selectedGroupIds.isNotEmpty)
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
                  child: Text("Send (${_selectedUserIds.length + _selectedGroupIds.length})"),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentChatsList() {
    return Column(
      children: [
        // Groups section
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _groupsStream,
          builder: (context, snapshot) {
            final groups = snapshot.data ?? [];
            if (groups.isEmpty) return const SizedBox();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Text("Groups", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                ...groups.map((g) => _buildUserTile(g, _selectedGroupIds.contains(g['uid']), isGroup: true)),
                const Divider(),
              ],
            );
          },
        ),
        // Users section
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: _recentChatsStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final users = snapshot.data ?? [];
              if (users.isEmpty && _selectedGroupIds.isEmpty) {
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
          ),
        ),
      ],
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

  Widget _buildUserTile(Map<String, dynamic> user, bool isSelected, {bool isGroup = false}) {
    final id = user['uid'];
    final name = user['username'] ?? (isGroup ? "Group" : "Anonymous");

    return ListTile(
      leading: isGroup 
        ? const GroupIcon(size: 40)
        : CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.secondary,
            child: Text(name[0].toUpperCase()),
          ),
      title: isGroup
        ? Text(name)
        : UsernameDisplay(
            userId: id,
            username: name,
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
      onTap: () => _toggleUserSelection(id, isGroup: isGroup),
    );
  }
}
