import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class GroupCreationSheet extends StatefulWidget {
  const GroupCreationSheet({super.key});

  @override
  State<GroupCreationSheet> createState() => _GroupCreationSheetState();
}

class _GroupCreationSheetState extends State<GroupCreationSheet> {
  final ChatService _chatService = ChatService();
  final UserService _userService = UserService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedUserIds = {};
  String _searchQuery = "";
  List<Map<String, dynamic>> _followingUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    final currentUserId = AuthService().getCurrentUser()!.uid;
    final users = await _userService.getFollowing(currentUserId);
    if (mounted) {
      setState(() {
        _followingUsers = users;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
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

  bool _isNameValid(String name) {
    final trimmed = name.trim();
    if (trimmed.length < 3 || trimmed.length > 30) return false;
    final regex = RegExp(r'^[a-zA-Z0-9._ -]+$');
    return regex.hasMatch(trimmed);
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (!_isNameValid(name) || _selectedUserIds.isEmpty) return;

    final List<String> memberIds = _selectedUserIds.toList();

    // Show loading
    setState(() => _isLoading = true);

    try {
      final groupId = await _chatService.createGroup(name, memberIds);
      if (mounted) {
        Navigator.pop(context, groupId); // Return the new group ID
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating group: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _followingUsers.where((user) {
      final username = user['username']?.toString().toLowerCase() ?? "";
      return username.contains(_searchQuery);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
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

          Text(
            'new_group'.tr(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),

          // Group Name field
          TextField(
            controller: _nameController,
            maxLength: 30,
            maxLines: 1,
            decoration: InputDecoration(
              hintText: 'group_name'.tr(),
              helperText: 'group_name_helper'.tr(),
              helperStyle: TextStyle(
                fontSize: 10,
                color: _isNameValid(_nameController.text) 
                    ? Colors.grey 
                    : Colors.red.shade300
              ),
              counterText: "",
              filled: true,
              fillColor: Theme.of(context).colorScheme.secondary,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // User search
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'search_following'.tr(),
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
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : filteredUsers.isEmpty
                    ? Center(child: Text('no_users_to_add'.tr()))
                    : ListView.builder(
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          final userId = user['uid'];
                          final isSelected = _selectedUserIds.contains(userId);
                          final username = user['username'] ?? "Anonymous";

                          return ListTile(
                            leading: ProfileAvatar(
                              userId: userId,
                              username: username,
                              radius: 20,
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
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey,
                                  width: 2,
                                ),
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check,
                                      size: 16, color: Colors.white)
                                  : null,
                            ),
                            onTap: () => _toggleUserSelection(userId),
                          );
                        },
                      ),
          ),

          // Create button
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isNameValid(_nameController.text) && _selectedUserIds.isNotEmpty)
                    ? _createGroup
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.surface,
                  disabledBackgroundColor: Colors.grey.shade800,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_isLoading ? 'creating'.tr() : '${'create_group'.tr()} (${_selectedUserIds.length})'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
