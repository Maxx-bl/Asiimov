import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class AddMembersSheet extends StatefulWidget {
  final String groupId;
  final List<String> existingMemberIds;

  const AddMembersSheet({
    super.key,
    required this.groupId,
    required this.existingMemberIds,
  });

  @override
  State<AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<AddMembersSheet> {
  final UserService _userService = UserService();
  final ChatService _chatService = ChatService();
  final String _currentUserId = AuthService().getCurrentUser()!.uid;
  final Set<String> _selectedUserIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  List<Map<String, dynamic>> _followingUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    final users = await _userService.getFollowing(_currentUserId);
    if (mounted) {
      setState(() {
        _followingUsers = users;
        _isLoading = false;
      });
    }
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

  Future<void> _addMembers() async {
    if (_selectedUserIds.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final List<String> newMemberIds = [
        ...widget.existingMemberIds,
        ..._selectedUserIds,
      ];
      await _chatService.updateGroupMembers(widget.groupId, newMemberIds);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error adding members: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableUsers = _followingUsers.where((user) {
      final userId = user['uid'];
      final username = user['username']?.toString().toLowerCase() ?? "";
      return !widget.existingMemberIds.contains(userId) && username.contains(_searchQuery);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Add Members",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'search_following'.tr().tr(),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).colorScheme.secondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
          ),
          const SizedBox(height: 16),

          // User List
          Expanded(
            child: _isLoading 
                ? Center(child: CircularProgressIndicator())
                : availableUsers.isEmpty
                    ? Center(child: Text('no_more_followers_to_add'.tr()))
                    : ListView.builder(
                        itemCount: availableUsers.length,
                        itemBuilder: (context, index) {
                          final user = availableUsers[index];
                          final userId = user['uid'];
                          final username = user['username'] ?? 'Unknown';
                          final isSelected = _selectedUserIds.contains(userId);

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: ProfileAvatar(
                              userId: userId,
                              username: username,
                              radius: 20,
                            ),
                            title: UsernameDisplay(userId: userId, username: username),
                            trailing: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
                                  width: 2,
                                ),
                                color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
                              ),
                              child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                            ),
                            onTap: () => _toggleUserSelection(userId),
                          );
                        },
                      ),
          ),

          const SizedBox(height: 16),

          // Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedUserIds.isNotEmpty && !_isLoading) ? _addMembers : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text("Add Selected (${_selectedUserIds.length})"),
            ),
          ),
        ],
      ),
    );
  }
}
