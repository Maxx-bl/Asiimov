import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:asiimov/services/user/user_service.dart';
import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CloseFriendsPage extends StatefulWidget {
  const CloseFriendsPage({super.key});

  @override
  State<CloseFriendsPage> createState() => _CloseFriendsPageState();
}

class _CloseFriendsPageState extends State<CloseFriendsPage> {
  final _userService = UserService();
  final _auth = FirebaseAuth.instance;
  final _scrollController = ScrollController();

  List<String> _mutualUids = [];
  final List<Map<String, dynamic>> _loadedUsers = [];
  bool _isLoadingMore = false;
  bool _isFirstLoad = true;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _fetchMutuals();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      _loadNextPage();
    }
  }

  Future<void> _fetchMutuals() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      if (!doc.exists) return;

      final userData = doc.data() ?? {};
      final followers = List<String>.from(userData['followers'] ?? []);
      final following = List<String>.from(userData['following'] ?? []);
      final closeFriends = List<String>.from(userData['closeFriends'] ?? []);

      // Mutual followers: intersection of followers and following
      final mutuals = followers.toSet().intersection(following.toSet()).toList();

      // Sort mutuals so that existing close friends are placed at the top of the list
      mutuals.sort((a, b) {
        final aIsCF = closeFriends.contains(a);
        final bIsCF = closeFriends.contains(b);
        if (aIsCF && !bIsCF) return -1;
        if (!aIsCF && bIsCF) return 1;
        return 0;
      });

      if (mounted) {
        setState(() {
          _mutualUids = mutuals;
        });
        await _loadNextPage();
      }
    } catch (e) {
      debugPrint('Error fetching mutual followers: $e');
      if (mounted) {
        setState(() {
          _isFirstLoad = false;
        });
      }
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore) return;
    final startIndex = _currentPage * 15;
    if (startIndex >= _mutualUids.length) {
      if (mounted) {
        setState(() {
          _isFirstLoad = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingMore = true;
      });
    }

    final endIndex = min(startIndex + 15, _mutualUids.length);
    final pageUids = _mutualUids.sublist(startIndex, endIndex);

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: pageUids)
          .get();

      final fetchedUsers = querySnapshot.docs.map((d) {
        final data = d.data();
        data['uid'] = d.id;
        return data;
      }).toList();

      // Ensure they are ordered consistent with pageUids
      final orderedUsers = <Map<String, dynamic>>[];
      for (final uid in pageUids) {
        final match = fetchedUsers.firstWhere(
          (u) => u['uid'] == uid,
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          orderedUsers.add(match);
        }
      }

      if (mounted) {
        setState(() {
          _loadedUsers.addAll(orderedUsers);
          _currentPage++;
          _isFirstLoad = false;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading mutual followers details: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _isFirstLoad = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('User not logged in')),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Close Friends'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _userService.getUserStream(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _isFirstLoad) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          final bool isEnabled = userData['closeFriendsEnabled'] ?? false;
          final List<String> closeFriendsList = List<String>.from(userData['closeFriends'] ?? []);

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: ListView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                children: [
                  // Global activation switch card
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                      ),
                    ),
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.people_alt_rounded,
                                    color: Colors.greenAccent.shade400,
                                    size: 26,
                                  ),
                                  const SizedBox(width: 16),
                                  Text(
                                    'Close Friends Feature',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Limit post visibility to selected mutual friends',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        CupertinoSwitch(
                          value: isEnabled,
                          activeTrackColor: Colors.greenAccent.shade400,
                          onChanged: (value) async {
                            await _userService.toggleCloseFriendsFeature(value);
                          },
                        ),
                      ],
                    ),
                  ),

                  if (isEnabled) ...[
                    const SizedBox(height: 24),
                    // Header with count
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Mutual Followers',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.shade400.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${closeFriendsList.length} Close Friends',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_loadedUsers.isEmpty && !_isLoadingMore)
                      Padding(
                        padding: const EdgeInsets.only(top: 40.0),
                        child: Center(
                          child: Text(
                            'No mutual followers yet.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      )
                    else ...[
                      Builder(
                        builder: (context) {
                          // Sort loaded users dynamically so close friends always float to the top
                          final sortedUsers = List<Map<String, dynamic>>.from(_loadedUsers);
                          sortedUsers.sort((a, b) {
                            final aUid = a['uid'] ?? '';
                            final bUid = b['uid'] ?? '';
                            final aIsCF = closeFriendsList.contains(aUid);
                            final bIsCF = closeFriendsList.contains(bUid);
                            if (aIsCF && !bIsCF) return -1;
                            if (!aIsCF && bIsCF) return 1;
                            return 0;
                          });

                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: sortedUsers.length + (_isLoadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == sortedUsers.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16.0),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }

                              final user = sortedUsers[index];
                              final uid = user['uid'] ?? '';
                              final username = user['username'] ?? 'Unknown';
                              final isCloseFriend = closeFriendsList.contains(uid);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8.0),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondary,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.03),
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                                  leading: ProfileAvatar(
                                    userId: uid,
                                    username: username,
                                    radius: 20,
                                  ),
                                  title: UsernameDisplay(
                                    userId: uid,
                                    username: username,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  trailing: Checkbox(
                                    activeColor: Colors.greenAccent.shade400,
                                    checkColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    value: isCloseFriend,
                                    onChanged: (bool? value) async {
                                      if (value != null) {
                                        await _userService.updateCloseFriend(uid, value);
                                      }
                                    },
                                  ),
                                ),
                              );
                            },
                          );
                        }
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
