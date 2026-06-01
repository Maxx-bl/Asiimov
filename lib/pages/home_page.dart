import 'dart:async';

import 'package:asiimov/components/group_creation_sheet.dart';
import 'package:asiimov/components/group_icon.dart';
import 'package:asiimov/components/typing_dots.dart';
import 'package:asiimov/components/user_tile.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/models/conversation.dart';
import 'package:asiimov/pages/chat_page.dart';
import 'package:asiimov/pages/profile_page.dart';
import 'package:asiimov/services/auth/auth_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/draft_service.dart';
import 'package:asiimov/services/encryption/conversation_key_service.dart';
import 'package:asiimov/services/encryption/encryption_service.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

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
                  hintText: 'search_user'.tr(),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 2),
                  hintStyle: TextStyle(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.45),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.inversePrimary,
                ),
                onChanged: (value) {
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    setState(() {
                      _searchQuery = value.trim().toLowerCase();
                      _searchLimit = 20;
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
                          color: Theme.of(context).colorScheme.inversePrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        iconSize: 18,
                      ),
                    );
                  })
                : Text('home'.tr())),
        foregroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!_isSearching) ...[
            GestureDetector(
              onTap: _openGroupCreation,
              child: Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.secondary,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.40),
                    width: 0.5,
                  ),
                ),
                child: Icon(
                  Icons.add,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: _startSearch,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.5),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),
          ],
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _stopSearch,
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
              if (snapshot.hasError) return Center(child: Text("error".tr()));
              if (snapshot.connectionState == ConnectionState.waiting &&
                  _searchLimit == 20) {
                return Center(child: CircularProgressIndicator());
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
          return Center(child: CircularProgressIndicator());
        }

        final conversations = snapshot.data ?? [];
        if (conversations.isEmpty) return _buildEmptyState();

        return ListView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 24),
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            final conv = conversations[index];
            final isUnread = conv.unreadCount > 0;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isUnread
                    ? Theme.of(context).colorScheme.secondary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: isUnread
                    ? Border.all(
                        color: Theme.of(context).primaryColor.withValues(alpha: 0.18),
                        width: 0.5,
                      )
                    : null,
              ),
              child: buildConversationItem(conv),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.secondary,
                border: Border.all(
                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.35),
                  width: 0.5,
                ),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 32,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _isSearching ? 'no_user_found'.tr() : 'no_conversations_yet'.tr(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.inversePrimary,
              ),
            ),
            if (!_isSearching) ...[
              const SizedBox(height: 8),
              Text(
                'Start a new conversation by tapping the compose button above.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget buildConversationItem(Conversation conv) {
    // Compute the Firestore chat room ID (matches chats/{id}/typing subcollection)
    final currentUid = authService.getCurrentUser()!.uid;
    final String chatRoomId;
    if (conv.isGroup) {
      chatRoomId = conv.id;
    } else {
      final ids = [currentUid, conv.id]..sort();
      chatRoomId = ids.join('_');
    }

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
    String messagePreview = "start_chatting".tr();
    if (conv.lastMessage != null) {
      try {
        final lastMsg = conv.lastMessage!;
        final rawMsg = lastMsg['message'];

        if (lastMsg['isSystemMessage'] == true) {
          messagePreview = rawMsg;
        } else {
          String decrypted;
          // Compute the real chatRoomId (groups use conv.id directly; private chats use sorted uid_uid)
          final myUid = authService.getCurrentUser()!.uid;
          final chatRoomId = conv.isGroup
              ? conv.id
              : ([myUid, conv.id]..sort()).join('_');
          // Use the ECDH-derived key for decryption.
          // Old messages (ECIES/legacy) will show blank — only new messages matter.
          decrypted = '';
          final ecdhKey = ConversationKeyService.getCachedEcdhKey(chatRoomId);
          if (ecdhKey != null) {
            try {
              decrypted = EncryptionService.decryptWithKey(rawMsg, ecdhKey);
            } catch (_) {}
          }
          final senderName =
              lastMsg['senderID'] == authService.getCurrentUser()!.uid
                  ? 'you'.tr()
                  : lastMsg['senderUsername'];

          String displayMsg =
              decrypted.isEmpty ? 'sent_attachment'.tr() : decrypted;

          if (conv.isGroup) {
            messagePreview = '$senderName: $displayMsg';
          } else {
            messagePreview =
                lastMsg['senderID'] == authService.getCurrentUser()!.uid
                    ? '${'you'.tr()}: $displayMsg'
                    : displayMsg;
          }
        }
      } catch (e) {
        messagePreview = "encrypted_message".tr();
      }
    }

    // Override with reaction preview if it's more recent than the last message
    if (conv.lastReaction != null) {
      final lastMsgTimestamp = conv.lastMessage?['timestamp'] as Timestamp?;
      final lastReactionTimestamp = conv.lastReaction!['timestamp'] as Timestamp?;
      final reactionIsNewer = lastReactionTimestamp != null &&
          (lastMsgTimestamp == null ||
              lastReactionTimestamp.compareTo(lastMsgTimestamp) > 0);

      if (reactionIsNewer) {
        final emoji = conv.lastReaction!['emoji'] as String? ?? '';
        final senderID = conv.lastReaction!['senderID'] as String?;
        final senderUsername = conv.lastReaction!['senderUsername'] as String? ?? '';
        final isMe = senderID == authService.getCurrentUser()!.uid;

        if (conv.isGroup) {
          messagePreview = isMe
              ? '${'you'.tr()} ${'reacted'.tr()} $emoji'
              : '$senderUsername ${'reacted'.tr()} $emoji';
        } else {
          messagePreview = isMe
              ? '${'you'.tr()} ${'reacted'.tr()} $emoji'
              : '$senderUsername ${'reacted'.tr()} $emoji';
        }
      }
    }

    // Override with unsent draft if present
    final draft = DraftService.get(conv.id);
    final hasDraft = draft != null && draft.isNotEmpty;
    if (hasDraft) messagePreview = draft;

    // Determine status (sent/seen) if I am the sender
    String? status;
    if (conv.lastMessage != null && !conv.isGroup) {
      final isMyMessage =
          conv.lastMessage!['senderID'] == authService.getCurrentUser()!.uid;
      if (isMyMessage) {
        status = conv.lastMessage!['isRead'] == true ? 'seen'.tr() : 'sent'.tr();
      }
    }

    return UserTile(
      text: conv.otherUsername,
      userId: conv.isGroup ? '' : conv.otherUserId,
      avatarRadius: 22,
      leading: conv.isGroup
          ? GroupIcon(size: 44, imageUrl: conv.groupIconUrl)
          : null,
      subtitle: StreamBuilder<List<String>>(
        stream: chatService.getTypingUsernamesStream(chatRoomId),
        builder: (context, snapshot) {
          final typers = snapshot.data ?? [];
          final indicatorColor =
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.6);

          if (hasDraft) {
            return Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: 'draft_prefix'.tr(),
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: messagePreview,
                  style: TextStyle(color: indicatorColor, fontSize: 13),
                ),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          }

          if (typers.isNotEmpty) {
            final String label;
            if (typers.length == 1) {
              label = 'x_is_typing'.tr(namedArgs: {'name': '@${typers[0]}'});
            } else if (typers.length == 2) {
              label = 'x_and_y_are_typing'.tr(
                  namedArgs: {'name1': '@${typers[0]}', 'name2': '@${typers[1]}'});
            } else {
              label = 'several_typing'.tr();
            }
            return Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: indicatorColor,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                TypingDots(color: indicatorColor),
              ],
            );
          }

          return Text(
            messagePreview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: conv.unreadCount > 0
                  ? Theme.of(context).colorScheme.primary
                  : indicatorColor,
              fontSize: 13,
              fontWeight:
                  conv.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
            ),
          );
        },
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
                  fontSize: 11,
                  color: status == 'seen'.tr()
                      ? Theme.of(context).primaryColor
                      : Colors.grey.shade400,
                  fontWeight: status == 'seen'.tr() ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          Text(
            dateString,
            style: TextStyle(
              color: conv.unreadCount > 0
                  ? Theme.of(context).primaryColor
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.50),
              fontSize: 11,
              fontWeight: conv.unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (conv.unreadCount > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                conv.unreadCount <= 9 ? '${conv.unreadCount}' : '9+',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
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
        ).then((_) {
          if (mounted) setState(() {});
        });
      },
    );
  }
}
