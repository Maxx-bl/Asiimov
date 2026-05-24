import 'dart:io';
import 'package:asiimov/components/add_members_sheet.dart';
import 'package:asiimov/components/group_icon.dart';
import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/image/image_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

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
          title: Text('rename_group'.tr()),
          content: TextField(
            controller: controller,
            maxLength: 30,
            maxLines: 1,
            decoration: InputDecoration(
              hintText: 'new_name'.tr().tr(),
              helperText: "3-30 chars: a-z, 0-9, . , - , _",
              errorText: _isNameValid(controller.text) ? null : 'invalid_name'.tr(),
              counterText: "",
            ),
            onChanged: (value) => setDialogState(() {}),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text("Cancel")),
            TextButton(
              onPressed: _isNameValid(controller.text) 
                ? () async {
                    final nav = Navigator.of(dialogContext);
                    await _chatService.renameGroup(widget.groupId, controller.text.trim());
                    if (mounted) nav.pop();
                    setState(() {}); // Refresh
                  }
                : null,
              child: Text('save'.tr()),
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
        title: Text('remove_member'.tr()),
        content: Text("Are you sure you want to remove @$username from the group?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text("Cancel")),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(dialogContext);
              final doc = await FirebaseFirestore.instance.collection('chats').doc(widget.groupId).get();
              final members = List<String>.from(doc.data()?['members'] ?? []);
              final newMembers = members.where((m) => m != uid).toList();
              
              await _chatService.updateGroupMembers(widget.groupId, newMembers.where((m) => m != _currentUserId).toList());
              if (mounted) nav.pop();
            },
            child: Text('remove'.tr(), style: TextStyle(color: Colors.red)),
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
        title: Text('leave_group'.tr()),
        content: Text('are_you_sure_you_want_to_leave'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text("Cancel")),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(dialogContext);
              final scaffold = ScaffoldMessenger.of(dialogContext);
              // Show loading
              showDialog(
                context: dialogContext,
                barrierDismissible: false,
                builder: (context) => Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor)),
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
            child: Text('leave'.tr(), style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _changeGroupPicture(String? currentUrl) async {
    final hasCurrentPicture = currentUrl != null && currentUrl.isNotEmpty;

    final action = await ImageService.showImageSourceSheet(context, showDeleteOption: hasCurrentPicture);
    if (action == null) return;

    final imageService = ImageService();

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Center(
          child: CircularProgressIndicator(color: Theme.of(context).primaryColor),
        ),
      );
    }

    if (action == 'delete') {
      final success = await imageService.deleteGroupProfilePicture(widget.groupId);
      if (mounted) Navigator.pop(context); // Pop loading

      if (success) {
        await _chatService.logGroupPictureUpdate(widget.groupId, true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('group_picture_deleted'.tr())),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('failed_to_delete_group_picture'.tr())),
          );
        }
      }
      return;
    }

    final source = action == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final pickedFile = await imageService.pickImage(source);
    if (pickedFile == null) {
      if (mounted) Navigator.pop(context); // Pop loading if cancelled
      return;
    }

    // Check file size (max 20MB)
    final length = await pickedFile.length();
    if (length > 20 * 1024 * 1024) {
      if (mounted) {
        Navigator.pop(context); // Pop loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File is too large (max 20MB).', style: TextStyle(color: Colors.white)), 
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final url = await imageService.uploadGroupProfilePicture(widget.groupId, pickedFile);

    if (mounted) Navigator.pop(context); // Pop loading

    if (url != null) {
      await _chatService.logGroupPictureUpdate(widget.groupId, false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('group_picture_updated'.tr())),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('failed_to_update_group_picture'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('group_settings'.tr()),
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
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
          
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data == null) return Center(child: Text('group_not_found'.tr()));

          final name = data['groupName'] ?? widget.groupName;
          final creatorId = data['creatorId'] ?? widget.creatorId;
          final members = List<String>.from(data['members'] ?? []);
          final groupIconUrl = data['groupIconUrl'] as String?;
          final isAdmin = _currentUserId == creatorId;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Group Header
              Center(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: isAdmin ? () => _changeGroupPicture(groupIconUrl) : null,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          GroupIcon(size: 80, imageUrl: groupIconUrl),
                          if (isAdmin)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                            ),
                        ],
                      ),
                    ),
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
              Text('settings'.tr(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text('mute_notifications'.tr()),
                value: _isMuted,
                onChanged: _toggleMute,
                activeThumbColor: Theme.of(context).primaryColor,
              ),
              
              const SizedBox(height: 32),

              // Members Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('members'.tr(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                      label: Text('add'.tr()),
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
                        leading: ProfileAvatar(
                          userId: uid,
                          username: username,
                          radius: 20,
                        ),
                        title: UsernameDisplay(userId: uid, username: username),
                        subtitle: isMemberAdmin ? Text('admin'.tr(), style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 12)) : null,
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
