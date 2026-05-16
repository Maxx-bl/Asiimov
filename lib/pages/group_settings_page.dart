import 'package:asiimov/components/add_members_sheet.dart';
import 'package:asiimov/components/group_icon.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class GroupSettingsPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String creatorId;

  const GroupSettingsPage({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.creatorId,
  });

  @override
  State<GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends State<GroupSettingsPage> {
  final ChatService _chatService = ChatService();
  final String _currentUserId = AuthService().getCurrentUser()!.uid;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _loadMuteStatus();
  }

  Future<void> _loadMuteStatus() async {
    final doc = await FirebaseFirestore.instance.collection('chats').doc(widget.groupId).get();
    final mutedBy = List<String>.from(doc.data()?['mutedBy'] ?? []);
    if (mounted) {
      setState(() {
        _isMuted = mutedBy.contains(_currentUserId);
      });
    }
  }

  bool _isNameValid(String name) {
    final trimmed = name.trim();
    if (trimmed.length < 3 || trimmed.length > 30) return false;
    final regex = RegExp(r'^[a-zA-Z0-9._ -]+$');
    return regex.hasMatch(trimmed);
  }

  void _renameGroup() {
    final controller = TextEditingController(text: widget.groupName);
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text("Rename Group"),
          content: TextField(
            controller: controller,
            maxLength: 30,
            maxLines: 1,
            decoration: InputDecoration(
              hintText: "New name",
              helperText: "3-30 chars: a-z, 0-9, . , - , _",
              errorText: _isNameValid(controller.text) ? null : "Invalid name",
              counterText: "",
            ),
            onChanged: (value) => setDialogState(() {}),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
            TextButton(
              onPressed: _isNameValid(controller.text) 
                ? () async {
                    final nav = Navigator.of(dialogContext);
                    await _chatService.renameGroup(widget.groupId, controller.text.trim());
                    if (mounted) nav.pop();
                    setState(() {}); // Refresh
                  }
                : null,
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  void _removeMember(String uid, String username) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Remove Member?"),
        content: Text("Are you sure you want to remove @$username from the group?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(dialogContext);
              final doc = await FirebaseFirestore.instance.collection('chats').doc(widget.groupId).get();
              final members = List<String>.from(doc.data()?['members'] ?? []);
              final newMembers = members.where((m) => m != uid).toList();
              
              await _chatService.updateGroupMembers(widget.groupId, newMembers.where((m) => m != _currentUserId).toList());
              if (mounted) nav.pop();
            },
            child: const Text("Remove", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _toggleMute(bool value) async {
    setState(() => _isMuted = value);
    await _chatService.toggleMuteGroup(widget.groupId, value);
  }

  void _leaveGroup() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Leave Group?"),
        content: const Text("Are you sure you want to leave this discussion?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(dialogContext);
              final scaffold = ScaffoldMessenger.of(dialogContext);
              // Show loading
              showDialog(
                context: dialogContext,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
              );

              try {
                await _chatService.leaveGroup(widget.groupId);
                if (mounted) {
                  // Pop loading dialog
                  nav.pop();
                  // Go back to home
                  nav.popUntil((route) => route.isFirst);
                }
              } catch (e) {
                if (mounted) {
                  nav.pop(); // Pop loading
                  scaffold.showSnackBar(
                    SnackBar(content: Text("Error leaving group: $e")),
                  );
                }
              }
            },
            child: const Text("Leave", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Group Settings"),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _leaveGroup,
            icon: const Icon(Icons.logout, color: Colors.red),
            tooltip: "Leave Group",
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('chats').doc(widget.groupId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) return const Center(child: Text("Group not found"));

          final name = data['groupName'] ?? widget.groupName;
          final creatorId = data['creatorId'] ?? widget.creatorId;
          final members = List<String>.from(data['members'] ?? []);
          final isAdmin = _currentUserId == creatorId;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Group Header
              Center(
                child: Column(
                  children: [
                    const GroupIcon(size: 80),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (isAdmin)
                          IconButton(
                            onPressed: _renameGroup,
                            icon: const Icon(Icons.edit, size: 20),
                          ),
                      ],
                    ),
                    Text(
                      "${members.length} members",
                      style: TextStyle(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Settings Section
              const Text("Settings", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text("Mute Notifications"),
                value: _isMuted,
                onChanged: _toggleMute,
                activeThumbColor: Colors.orange,
              ),
              
              const SizedBox(height: 32),

              // Members Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Members", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (isAdmin)
                    TextButton.icon(
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => AddMembersSheet(
                            groupId: widget.groupId,
                            existingMemberIds: members,
                          ),
                        );
                      },
                      icon: const Icon(Icons.person_add, size: 18),
                      label: const Text("Add"),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Member List
              FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: members).get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) return const SizedBox();
                  
                  final users = userSnapshot.data!.docs;
                  return Column(
                    children: users.map((userDoc) {
                      final userData = userDoc.data() as Map<String, dynamic>;
                      final uid = userDoc.id;
                      final username = userData['username'] ?? 'Unknown';
                      final isMemberAdmin = uid == creatorId;

                      return ListTile(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ProfilePage(
                                userId: uid,
                                username: username,
                              ),
                            ),
                          );
                        },
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.secondary,
                          child: Text(username[0].toUpperCase()),
                        ),
                        title: UsernameDisplay(userId: uid, username: username),
                        subtitle: isMemberAdmin ? const Text("Admin", style: TextStyle(color: Colors.orange, fontSize: 12)) : null,
                        trailing: (isAdmin && uid != _currentUserId)
                            ? IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                onPressed: () => _removeMember(uid, username),
                              )
                            : null,
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }
}
