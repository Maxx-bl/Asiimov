import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/utils/report_reasons_helper.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/widgets/safe_network_image.dart';
import 'package:asiimov/services/admin/admin_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AdminService _adminService = AdminService();
  final PostService _postService = PostService();
  final ChatService _chatService = ChatService();

  // Search controllers
  final TextEditingController _userSearchController = TextEditingController();

  // Paginated user management lists
  final List<DocumentSnapshot> _users = [];
  bool _usersLoading = false;
  bool _usersHasMore = true;
  DocumentSnapshot? _usersLastDoc;
  final ScrollController _usersScrollController = ScrollController();

  // Suspended users lists
  final List<DocumentSnapshot> _suspendedUsers = [];
  bool _suspendedLoading = false;
  bool _suspendedHasMore = true;
  DocumentSnapshot? _suspendedLastDoc;
  final ScrollController _suspendedScrollController = ScrollController();

  // Reports lists
  final List<DocumentSnapshot> _reports = [];
  bool _reportsLoading = false;
  bool _reportsHasMore = true;
  DocumentSnapshot? _reportsLastDoc;
  final ScrollController _reportsScrollController = ScrollController();
  String _selectedReportFilter = 'all'; // 'all', 'posts_comments', 'chats'

  // Resolved reports lists
  final List<DocumentSnapshot> _resolvedReports = [];
  bool _resolvedReportsLoading = false;
  bool _resolvedReportsHasMore = true;
  DocumentSnapshot? _resolvedReportsLastDoc;
  final ScrollController _resolvedReportsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    // Fetch initial datasets
    _fetchUsers(refresh: true);
    _fetchSuspendedUsers(refresh: true);
    _fetchReports(refresh: true);
    _fetchResolvedReports(refresh: true);

    // Setup scroll listeners
    _usersScrollController.addListener(() {
      if (_usersScrollController.position.pixels >= _usersScrollController.position.maxScrollExtent - 200) {
        _fetchUsers();
      }
    });

    _suspendedScrollController.addListener(() {
      if (_suspendedScrollController.position.pixels >= _suspendedScrollController.position.maxScrollExtent - 200) {
        _fetchSuspendedUsers();
      }
    });

    _reportsScrollController.addListener(() {
      if (_reportsScrollController.position.pixels >= _reportsScrollController.position.maxScrollExtent - 200) {
        _fetchReports();
      }
    });

    _resolvedReportsScrollController.addListener(() {
      if (_resolvedReportsScrollController.position.pixels >= _resolvedReportsScrollController.position.maxScrollExtent - 200) {
        _fetchResolvedReports();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _userSearchController.dispose();
    _usersScrollController.dispose();
    _suspendedScrollController.dispose();
    _reportsScrollController.dispose();
    _resolvedReportsScrollController.dispose();
    super.dispose();
  }

  // --- PAGINATED FETCH METHODS (15 by 15) ---

  Future<void> _fetchUsers({bool refresh = false}) async {
    if (_usersLoading || (!refresh && !_usersHasMore)) return;

    setState(() => _usersLoading = true);

    try {
      final queryText = _userSearchController.text.trim().toLowerCase();
      Query query = FirebaseFirestore.instance.collection('users').limit(15);

      if (queryText.isNotEmpty) {
        query = query
            .where('username', isGreaterThanOrEqualTo: queryText)
            .where('username', isLessThanOrEqualTo: '$queryText\uf8ff');
      }

      if (!refresh && _usersLastDoc != null) {
        query = query.startAfterDocument(_usersLastDoc!);
      }

      final snapshot = await query.get();

      if (refresh) {
        _users.clear();
        _usersLastDoc = null;
      }

      if (snapshot.docs.isNotEmpty) {
        _users.addAll(snapshot.docs);
        _usersLastDoc = snapshot.docs.last;
        _usersHasMore = snapshot.docs.length == 15;
      } else {
        _usersHasMore = false;
      }
    } catch (e) {
      debugPrint("Error fetching users: $e");
    } finally {
      if (mounted) setState(() => _usersLoading = false);
    }
  }

  Future<void> _fetchSuspendedUsers({bool refresh = false}) async {
    if (_suspendedLoading || (!refresh && !_suspendedHasMore)) return;

    setState(() => _suspendedLoading = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('users')
          .where('isSuspended', isEqualTo: true)
          .limit(15);

      if (!refresh && _suspendedLastDoc != null) {
        query = query.startAfterDocument(_suspendedLastDoc!);
      }

      final snapshot = await query.get();

      if (refresh) {
        _suspendedUsers.clear();
        _suspendedLastDoc = null;
      }

      if (snapshot.docs.isNotEmpty) {
        _suspendedUsers.addAll(snapshot.docs);
        _suspendedLastDoc = snapshot.docs.last;
        _suspendedHasMore = snapshot.docs.length == 15;
      } else {
        _suspendedHasMore = false;
      }
    } catch (e) {
      debugPrint("Error fetching suspended users: $e");
    } finally {
      if (mounted) setState(() => _suspendedLoading = false);
    }
  }

  Future<void> _fetchReports({bool refresh = false}) async {
    if (_reportsLoading || (!refresh && !_reportsHasMore)) return;

    setState(() => _reportsLoading = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('reports')
          .where('status', isEqualTo: 'pending')
          .limit(15);

      if (!refresh && _reportsLastDoc != null) {
        query = query.startAfterDocument(_reportsLastDoc!);
      }

      final snapshot = await query.get();

      if (refresh) {
        _reports.clear();
        _reportsLastDoc = null;
      }

      if (snapshot.docs.isNotEmpty) {
        _reports.addAll(snapshot.docs);
        // Sort in-memory to bypass Firestore composite index requirement
        _reports.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>?;
          final bData = b.data() as Map<String, dynamic>?;
          final aTime = aData?['timestamp'] as Timestamp?;
          final bTime = bData?['timestamp'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });
        _reportsLastDoc = snapshot.docs.last;
        _reportsHasMore = snapshot.docs.length == 15;
      } else {
        _reportsHasMore = false;
      }
    } catch (e) {
      debugPrint("Error fetching reports: $e");
    } finally {
      if (mounted) setState(() => _reportsLoading = false);
    }
  }

  Future<void> _fetchResolvedReports({bool refresh = false}) async {
    if (_resolvedReportsLoading || (!refresh && !_resolvedReportsHasMore)) return;

    setState(() => _resolvedReportsLoading = true);

    try {
      Query query = FirebaseFirestore.instance
          .collection('reports')
          .where('status', isEqualTo: 'resolved')
          .limit(15);

      if (!refresh && _resolvedReportsLastDoc != null) {
        query = query.startAfterDocument(_resolvedReportsLastDoc!);
      }

      final snapshot = await query.get();

      if (refresh) {
        _resolvedReports.clear();
        _resolvedReportsLastDoc = null;
      }

      if (snapshot.docs.isNotEmpty) {
        _resolvedReports.addAll(snapshot.docs);
        // Sort in-memory to bypass Firestore composite index requirement
        _resolvedReports.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>?;
          final bData = b.data() as Map<String, dynamic>?;
          final aTime = aData?['resolvedAt'] as Timestamp?;
          final bTime = bData?['resolvedAt'] as Timestamp?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return bTime.compareTo(aTime);
        });
        _resolvedReportsLastDoc = snapshot.docs.last;
        _resolvedReportsHasMore = snapshot.docs.length == 15;
      } else {
        _resolvedReportsHasMore = false;
      }
    } catch (e) {
      debugPrint("Error fetching resolved reports: $e");
    } finally {
      if (mounted) setState(() => _resolvedReportsLoading = false);
    }
  }

  // --- MODERATION ACTIONS ---

  void _showOfficialBadgeDialog(String userId, String username, bool currentVal) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(currentVal ? 'Remove Official Badge' : 'Grant Official Badge'),
        content: Text('Are you sure you want to ${currentVal ? "remove" : "grant"} the verified badge ${currentVal ? "from" : "to"} @$username?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirm', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _adminService.toggleOfficialBadge(userId, !currentVal);
        UsernameDisplay.clearCacheForUser(userId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Verification status updated for @$username'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchUsers(refresh: true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  void _showSuspensionDialog(String userId, String username, {bool isSuspended = false}) async {
    if (isSuspended) {
      // Unsuspend confirmation
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Unsuspend User'),
          content: Text('Are you sure you want to reinstate @$username\'s account?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Unsuspend', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        try {
          await _adminService.unsuspendUser(userId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('@$username successfully reinstated!'), backgroundColor: Colors.green),
            );
            _fetchUsers(refresh: true);
            _fetchSuspendedUsers(refresh: true);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.redAccent),
            );
          }
        }
      }
    } else {
      // Suspend with reason dialog
      final reasonController = TextEditingController();
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Suspend @$username'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Provide a clear reason for the suspension. This will be shown to the user.'),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter reason (e.g., Harassment, SPAM...)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Suspend', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm == true && reasonController.text.trim().isNotEmpty) {
        try {
          await _adminService.suspendUser(userId, reasonController.text.trim());

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('@$username suspended successfully.'), backgroundColor: Colors.redAccent),
            );
            _fetchUsers(refresh: true);
            _fetchSuspendedUsers(refresh: true);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.redAccent),
            );
          }
        }
      }
    }
  }

  void _showDeleteContentDialog(DocumentSnapshot reportDoc) async {
    final reportData = reportDoc.data() as Map<String, dynamic>;
    final reportId = reportDoc.id;
    final type = reportData['type'] as String;
    final authorId = reportData['postAuthorId'] ?? reportData['commentAuthorId'] ?? reportData['messageOwnerId'];

    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Reported $type'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to delete this reported $type? This action is permanent.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason for deletion',
                  hintText: 'e.g. Inappropriate content, Hate speech, Spam...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please provide a reason.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final reason = reasonController.text.trim();
      try {
        if (type == 'post') {
          final postId = reportData['postId'] as String;
          await _postService.deletePost(postId);
        } else if (type == 'comment') {
          final commentPath = reportData['commentPath'] as String;
          await _postService.deleteComment(commentPath);
        } else if (type == 'message') {
          final chatRoomId = reportData['chatRoomId'] as String;
          final messageId = reportData['messageId'] as String;
          await _chatService.deleteMessageByRoomId(chatRoomId, messageId);
        }

        // Resolve the report and store the exact deletion reason
        await _adminService.resolveReport(reportId, action: 'deleted', reason: reason);

        // Store the active warning warning on the user's account in Firestore
        if (authorId != null) {
          await FirebaseFirestore.instance.collection('users').doc(authorId).update({
            'activeWarning': {
              'reason': reason,
              'contentType': type,
              'timestamp': FieldValue.serverTimestamp(),
            }
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Content deleted, warning sent to user, and case resolved!'), backgroundColor: Colors.green),
          );
          _fetchReports(refresh: true);
          _fetchResolvedReports(refresh: true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  void _showDismissReportDialog(String reportId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Dismiss Report'),
        content: const Text('Are you sure you want to dismiss this report? The content will remain in the app, and the report will be resolved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Dismiss', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _adminService.resolveReport(reportId, action: 'dismissed');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report dismissed successfully!'), backgroundColor: Colors.green),
          );
          _fetchReports(refresh: true);
          _fetchResolvedReports(refresh: true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  // --- RENDERING WIDGETS ---

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0C0F14) : Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          'ADMIN PANEL',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
        foregroundColor: Colors.redAccent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.redAccent,
          labelColor: Colors.redAccent,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline), text: 'Users'),
            Tab(icon: Icon(Icons.block_outlined), text: 'Suspended'),
            Tab(icon: Icon(Icons.gavel_outlined), text: 'Reports'),
            Tab(icon: Icon(Icons.history_outlined), text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUsersTab(isDarkMode),
          _buildSuspendedTab(isDarkMode),
          _buildReportsTab(isDarkMode),
          _buildResolvedReportsTab(isDarkMode),
        ],
      ),
    );
  }

  // TAB 1: USERS
  Widget _buildUsersTab(bool isDarkMode) {
    return Column(
      children: [
        // Search user bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _userSearchController,
            decoration: InputDecoration(
              hintText: 'Search user by username...',
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                onPressed: () {
                  _userSearchController.clear();
                  _fetchUsers(refresh: true);
                },
              ),
              filled: true,
              fillColor: isDarkMode ? const Color(0xFF171D26) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) {
              _fetchUsers(refresh: true);
            },
          ),
        ),

        Expanded(
          child: _users.isEmpty && _usersLoading
              ? const Center(child: CircularProgressIndicator())
              : _users.isEmpty
                  ? const Center(child: Text('No users found.'))
                  : RefreshIndicator(
                      onRefresh: () => _fetchUsers(refresh: true),
                      child: ListView.builder(
                        controller: _usersScrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _users.length + (_usersLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _users.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final userDoc = _users[index];
                          final userData = userDoc.data() as Map<String, dynamic>;
                          final userId = userDoc.id;
                          final username = userData['username'] as String? ?? 'User';
                          final isSuspended = userData['isSuspended'] == true;
                          final official = userData['official'] == true;
                          final reportsCount = userData['reportsCount'] as int? ?? 0;

                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            color: isDarkMode ? const Color(0xFF171D26) : Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: ProfileAvatar(userId: userId, username: username, radius: 20),
                              title: Row(
                                children: [
                                  Text(
                                    username,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  if (official) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.verified, color: Colors.blue, size: 16),
                                  ],
                                  if (isSuspended) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.redAccent.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'SUSPENDED',
                                        style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                'Reports filed: $reportsCount',
                                style: TextStyle(
                                  color: reportsCount > 0 ? Colors.redAccent : Colors.grey,
                                  fontWeight: reportsCount > 0 ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Official badge toggle
                                  IconButton(
                                    icon: Icon(
                                      official ? Icons.verified : Icons.verified_outlined,
                                      color: official ? Colors.blue : Colors.grey,
                                    ),
                                    onPressed: () => _showOfficialBadgeDialog(userId, username, official),
                                  ),
                                  // Suspension button
                                  IconButton(
                                    icon: Icon(
                                      isSuspended ? Icons.lock_open : Icons.lock_outline,
                                      color: isSuspended ? Colors.green : Colors.redAccent,
                                    ),
                                    onPressed: () => _showSuspensionDialog(userId, username, isSuspended: isSuspended),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  // TAB 2: SUSPENDED USERS
  Widget _buildSuspendedTab(bool isDarkMode) {
    return _suspendedUsers.isEmpty && _suspendedLoading
        ? const Center(child: CircularProgressIndicator())
        : _suspendedUsers.isEmpty
            ? const Center(child: Text('No suspended users listed.'))
            : RefreshIndicator(
                onRefresh: () => _fetchSuspendedUsers(refresh: true),
                child: ListView.builder(
                  controller: _suspendedScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _suspendedUsers.length + (_suspendedLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _suspendedUsers.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final userDoc = _suspendedUsers[index];
                    final userData = userDoc.data() as Map<String, dynamic>;
                    final userId = userDoc.id;
                    final username = userData['username'] as String? ?? 'User';
                    final reason = userData['suspensionReason'] as String? ?? 'No reason provided.';

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      color: isDarkMode ? const Color(0xFF171D26) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: ProfileAvatar(userId: userId, username: username, radius: 20),
                        title: Text(
                          username,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'Reason: $reason',
                              style: TextStyle(color: isDarkMode ? Colors.grey.shade300 : Colors.black87),
                            ),
                          ],
                        ),
                        trailing: ElevatedButton(
                          onPressed: () => _showSuspensionDialog(userId, username, isSuspended: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Reinstate', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  },
                ),
              );
  }

  Widget _buildReportReasonsSection(
    Map<String, dynamic> reportData,
    bool isDarkMode,
  ) {
    final reasons = ReportReasonsHelper.parseReportReasons(reportData);
    if (reasons.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Report reason${reasons.length > 1 ? 's' : ''}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDarkMode ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 6),
        ...reasons.map((entry) {
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: isDarkMode ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reasons.length > 1)
                  Text(
                    '@${entry['username']}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                if (reasons.length > 1) const SizedBox(height: 2),
                Text(
                  entry['reason']!,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildReportedMediaPreview(Map<String, dynamic> reportData) {
    final type = reportData['type'] as String;

    Future<DocumentSnapshot?> getSourceDoc() async {
      try {
        if (type == 'post') {
          final postId = reportData['postId'] as String?;
          if (postId != null && postId.isNotEmpty) {
            return await FirebaseFirestore.instance.collection('posts').doc(postId).get();
          }
        } else if (type == 'comment') {
          final commentPath = reportData['commentPath'] as String?;
          if (commentPath != null && commentPath.isNotEmpty) {
            return await FirebaseFirestore.instance.doc(commentPath).get();
          }
        } else if (type == 'message') {
          final chatRoomId = reportData['chatRoomId'] as String?;
          final messageId = reportData['messageId'] as String?;
          if (chatRoomId != null && messageId != null && chatRoomId.isNotEmpty && messageId.isNotEmpty) {
            return await FirebaseFirestore.instance
                .collection('chats')
                .doc(chatRoomId)
                .collection('messages')
                .doc(messageId)
                .get();
          }
        }
      } catch (_) {}
      return null;
    }

    return FutureBuilder<DocumentSnapshot?>(
      future: getSourceDoc(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final doc = snapshot.data;
        final exists = doc != null && doc.exists;

        if (exists) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null) {
            if (type == 'message') {
              final msgType = data['messageType'] as String? ?? 'text';
              if (msgType == 'audio') {
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mic, color: Theme.of(context).primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text('Active Voice Message (Audio)', style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 13, fontWeight: FontWeight.w500)),
                    ],
                  ),
                );
              } else if (msgType == 'photo') {
                final attachments = data['attachments'] as List<dynamic>?;
                final url = (attachments != null && attachments.isNotEmpty) ? attachments[0]['url'] as String? : null;
                if (url != null) {
                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    height: 120,
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SafeNetworkImage(url: url, fit: BoxFit.cover),
                    ),
                  );
                }
              } else if (msgType == 'instant_photo') {
                final instant = data['instantAttachment'] as Map<String, dynamic>?;
                final url = instant?['url'] as String?;
                if (url != null) {
                  return Container(
                    margin: const EdgeInsets.only(top: 8),
                    height: 120,
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SafeNetworkImage(url: url, fit: BoxFit.cover),
                    ),
                  );
                }
              } else if (msgType == 'shared_post') {
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.share, color: Theme.of(context).primaryColor, size: 18),
                      const SizedBox(width: 8),
                      const Text('Active Shared Post Link', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                );
              }
            } else {
              final attachments = data['attachments'] as List<dynamic>? ?? (data['attachment'] != null ? [data['attachment']] : null);
              if (attachments != null && attachments.isNotEmpty) {
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: attachments.length,
                    itemBuilder: (context, i) {
                      final att = attachments[i];
                      final url = att['url'] as String?;
                      final fileType = att['type'] as String? ?? 'image';
                      if (url == null) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: fileType.contains('video')
                              ? Container(
                                  color: Colors.black,
                                  width: 80,
                                  child: const Icon(Icons.play_circle_outline, color: Colors.white),
                                )
                              : SafeNetworkImage(url: url, width: 80, height: 80, fit: BoxFit.cover),
                        ),
                      );
                    },
                  ),
                );
              }
            }
          }
        }

        final cachedMsgType = reportData['messageType'] as String? ?? 'text';
        final cachedAttachmentTypes = List<String>.from(reportData['attachmentTypes'] ?? []);

        if (type == 'message') {
          if (cachedMsgType != 'text') {
            String displayType = cachedMsgType;
            if (cachedMsgType == 'audio') displayType = 'voice message';
            if (cachedMsgType == 'instant_photo') displayType = 'instant photo';
            if (cachedMsgType == 'shared_post') displayType = 'shared post';
            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Media deleted ($displayType)',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }
        } else {
          if (cachedAttachmentTypes.isNotEmpty) {
            final displayTypes = cachedAttachmentTypes.join(', ');
            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Media deleted ($displayTypes)',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }
        }

        return const SizedBox();
      },
    );
  }

  // Filter button helper
  Widget _buildFilterButton(String value, String label, bool isDarkMode) {
    final isSelected = _selectedReportFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedReportFilter = value;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDarkMode ? Colors.white12 : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected && !isDarkMode
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? (isDarkMode ? Colors.white : Colors.black87)
                  : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  // TAB 3: REPORTS
  Widget _buildReportsTab(bool isDarkMode) {
    final filteredReports = _reports.where((report) {
      final reportData = report.data() as Map<String, dynamic>;
      final type = reportData['type'] as String? ?? 'post';
      if (_selectedReportFilter == 'posts_comments') {
        return type == 'post' || type == 'comment';
      } else if (_selectedReportFilter == 'chats') {
        return type == 'message';
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Premium Segmented Filter Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Container(
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF171D26) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDarkMode ? Colors.white10 : Colors.grey.shade200),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _buildFilterButton('all', 'All Reports', isDarkMode),
                _buildFilterButton('posts_comments', 'Posts & Comments', isDarkMode),
                _buildFilterButton('chats', 'Chats & Media', isDarkMode),
              ],
            ),
          ),
        ),

        // Main List Content
        Expanded(
          child: _reports.isEmpty && _reportsLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredReports.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.grey, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _selectedReportFilter == 'all'
                                ? 'Perfect! No pending report cases.'
                                : 'No pending reports in this category.',
                            style: const TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _fetchReports(refresh: true),
                      child: ListView.builder(
                        controller: _reportsScrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: filteredReports.length + (_reportsLoading ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == filteredReports.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          final reportDoc = filteredReports[index];
                          final reportData = reportDoc.data() as Map<String, dynamic>;
                          final reportId = reportDoc.id;
                          final type = reportData['type'] as String? ?? 'post';

                          // Get values safely
                          final reporter = reportData['reportedByUsername'] as String? ?? 'Anonymous';
                          final date = (reportData['timestamp'] as Timestamp?)?.toDate();
                          final reportCount = reportData['reportCount'] as int? ?? 1;

                          String content = '';
                          String author = 'Anonymous';
                          String authorId = '';

                          if (type == 'post') {
                            content = reportData['postContent'] as String? ?? '';
                            author = reportData['postAuthorUsername'] as String? ?? 'Anonymous';
                            authorId = reportData['postAuthorId'] as String? ?? '';
                          } else if (type == 'comment') {
                            content = reportData['commentContent'] as String? ?? '';
                            author = reportData['commentAuthorUsername'] as String? ?? 'Anonymous';
                            authorId = reportData['commentAuthorId'] as String? ?? '';
                          } else if (type == 'message') {
                            content = reportData['messageContent'] as String? ?? '';
                            author = reportData['messageAuthorUsername'] as String? ?? 'Anonymous';
                            authorId = reportData['messageOwnerId'] as String? ?? '';
                          }

                          Color typeColor = Colors.orange;
                          if (type == 'comment') typeColor = Colors.purple;
                          if (type == 'message') typeColor = Colors.blue;

                          return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: isDarkMode ? const Color(0xFF171D26) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Case type and date
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: typeColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: typeColor.withValues(alpha: 0.2)),
                                      ),
                                      child: Text(
                                        type.toUpperCase(),
                                        style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (reportCount > 1) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                                        ),
                                        child: Text(
                                          'REPORTED $reportCount TIMES',
                                          style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  date != null ? '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}' : '',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Reported content preview
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDarkMode ? Colors.black26 : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDarkMode ? Colors.white10 : Colors.grey.shade200),
                              ),
                              child: Text(
                                content != '' ? content : '[Media Content]',
                                style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                              ),
                            ),
                            _buildReportedMediaPreview(reportData),
                            _buildReportReasonsSection(reportData, isDarkMode),
                            const SizedBox(height: 12),

                            // Author / Reporter info
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Author: @$author',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(width: 8),
                                        FutureBuilder<DocumentSnapshot>(
                                          future: FirebaseFirestore.instance.collection('users').doc(authorId).get(),
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                                              final userData = snapshot.data!.data() as Map<String, dynamic>?;
                                              final count = userData?['reportsCount'] as int? ?? 0;
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                                                ),
                                                child: Text(
                                                  '$count total reports',
                                                  style: const TextStyle(
                                                    color: Colors.redAccent,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              );
                                            }
                                            return const SizedBox();
                                          },
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'Reported by: @$reporter',
                                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 24),

                            // Action buttons
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.spaceBetween,
                              children: [
                                // Dismiss report without deleting
                                OutlinedButton.icon(
                                  onPressed: () => _showDismissReportDialog(reportId),
                                  icon: const Icon(Icons.close, size: 14),
                                  label: const Text('Dismiss', style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.green,
                                    side: const BorderSide(color: Colors.green),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                                
                                // Suspend Author
                                OutlinedButton.icon(
                                  onPressed: () => _showSuspensionDialog(authorId, author),
                                  icon: const Icon(Icons.block, size: 14),
                                  label: const Text('Suspend', style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                    side: const BorderSide(color: Colors.redAccent),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),

                                // Delete Content
                                ElevatedButton.icon(
                                  onPressed: () => _showDeleteContentDialog(reportDoc),
                                  icon: const Icon(Icons.delete_outline, size: 14),
                                  label: const Text('Delete', style: TextStyle(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildResolvedReportsTab(bool isDarkMode) {
    return _resolvedReports.isEmpty && _resolvedReportsLoading
        ? const Center(child: CircularProgressIndicator())
        : _resolvedReports.isEmpty
            ? const Center(child: Text('No resolved reports history.'))
            : RefreshIndicator(
                onRefresh: () => _fetchResolvedReports(refresh: true),
                child: ListView.builder(
                  controller: _resolvedReportsScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _resolvedReports.length + (_resolvedReportsLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _resolvedReports.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final reportDoc = _resolvedReports[index];
                    final reportData = reportDoc.data() as Map<String, dynamic>;
                    final type = reportData['type'] as String? ?? 'post';

                    final reporter = reportData['reportedByUsername'] as String? ?? 'Anonymous';
                    final date = (reportData['timestamp'] as Timestamp?)?.toDate();
                    final resolvedDate = (reportData['resolvedAt'] as Timestamp?)?.toDate();
                    final resolutionAction = reportData['resolutionAction'] as String? ?? 'resolved';
                    final reportCount = reportData['reportCount'] as int? ?? 1;

                    String content = '';
                    String author = 'Anonymous';

                    if (type == 'post') {
                      content = reportData['postContent'] as String? ?? '';
                      author = reportData['postAuthorUsername'] as String? ?? 'Anonymous';
                    } else if (type == 'comment') {
                      content = reportData['commentContent'] as String? ?? '';
                      author = reportData['commentAuthorUsername'] as String? ?? 'Anonymous';
                    } else if (type == 'message') {
                      content = reportData['messageContent'] as String? ?? '';
                      author = reportData['messageAuthorUsername'] as String? ?? 'Anonymous';
                    }

                    Color typeColor = Colors.orange;
                    if (type == 'comment') typeColor = Colors.purple;
                    if (type == 'message') typeColor = Colors.blue;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: isDarkMode ? const Color(0xFF171D26) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: typeColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: typeColor.withValues(alpha: 0.2)),
                                      ),
                                      child: Text(
                                        type.toUpperCase(),
                                        style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    if (reportCount > 1) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                                        ),
                                        child: Text(
                                          'REPORTED $reportCount TIMES',
                                          style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  date != null ? '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}' : '',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDarkMode ? Colors.black26 : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: isDarkMode ? Colors.white10 : Colors.grey.shade200),
                              ),
                              child: Text(
                                content != '' ? content : '[Media Content]',
                                style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
                              ),
                            ),
                            _buildReportedMediaPreview(reportData),
                            _buildReportReasonsSection(reportData, isDarkMode),
                            const SizedBox(height: 12),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Author: @$author',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Reported by: @$reporter',
                                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 24),

                            // Resolved Status Indicator (No action buttons!)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      resolutionAction == 'deleted'
                                          ? Icons.delete_outline
                                          : resolutionAction == 'dismissed'
                                              ? Icons.gavel_outlined
                                              : Icons.check_circle_outline,
                                      color: resolutionAction == 'deleted'
                                          ? Colors.redAccent
                                          : resolutionAction == 'dismissed'
                                              ? Colors.green
                                              : Colors.grey,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      resolutionAction == 'deleted'
                                          ? 'Content Deleted'
                                          : resolutionAction == 'dismissed'
                                              ? 'Report Dismissed'
                                              : 'Resolved',
                                      style: TextStyle(
                                        color: resolutionAction == 'deleted'
                                            ? Colors.redAccent
                                            : resolutionAction == 'dismissed'
                                                ? Colors.green
                                                : Colors.grey,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                if (resolvedDate != null)
                                  Text(
                                    '${resolvedDate.day}/${resolvedDate.month} ${resolvedDate.hour}:${resolvedDate.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                              ],
                            ),
                            if (reportData['resolutionReason'] != null && (reportData['resolutionReason'] as String).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDarkMode ? Colors.black12 : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isDarkMode ? Colors.white10 : Colors.grey.shade100),
                                ),
                                child: Text(
                                  'Reason: "${reportData['resolutionReason']}"',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
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
