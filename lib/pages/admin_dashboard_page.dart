import 'package:asiimov/components/profile_avatar.dart';
import 'package:asiimov/utils/report_reasons_helper.dart';
import 'package:asiimov/components/username_display.dart';
import 'package:asiimov/widgets/safe_network_image.dart';
import 'package:asiimov/services/admin/admin_service.dart';
import 'package:asiimov/services/chat/chat_service.dart';
import 'package:asiimov/services/post/post_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

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

  // --- Admin UI tokens (neutral, low-chrome) ---

  Color _surfaceColor(bool isDark) =>
      isDark ? const Color(0xFF0E1116) : const Color(0xFFF4F5F7);

  Color _cardColor(bool isDark) =>
      isDark ? const Color(0xFF161B22) : Colors.white;

  Color _borderColor(bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300;

  Color _mutedColor(bool isDark) =>
      isDark ? Colors.white60 : Colors.black54;

  Color _fillColor(bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade100;

  ShapeBorder _cardShape(bool isDark) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _borderColor(isDark)),
      );

  Widget _chip(String label, bool isDark, {bool emphasized = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: emphasized ? _fillColor(isDark) : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor(isDark)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: emphasized
              ? (isDark ? Colors.white : Colors.black87)
              : _mutedColor(isDark),
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'post':
        return 'Post';
      case 'comment':
        return 'Comment';
      case 'message':
        return 'Message';
      default:
        return type;
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? Theme.of(context).colorScheme.errorContainer
            : null,
      ),
    );
  }

  ButtonStyle _adminOutlinedStyle(bool isDark) => OutlinedButton.styleFrom(
        foregroundColor: isDark ? Colors.white70 : Colors.black87,
        side: BorderSide(color: _borderColor(isDark)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      );

  ButtonStyle _adminFilledStyle(bool isDark) => FilledButton.styleFrom(
        backgroundColor: isDark ? Colors.white : Colors.grey.shade900,
        foregroundColor: isDark ? Colors.black87 : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
      );

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
        title: Text(currentVal ? 'remove_official_badge'.tr() : 'grant_official_badge'.tr()),
        content: Text('Are you sure you want to ${currentVal ? "remove" : "grant"} the verified badge ${currentVal ? "from" : "to"} @$username?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
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
          _showSnack('Verification status updated for @$username');
          _fetchUsers(refresh: true);
        }
      } catch (e) {
        if (mounted) {
          _showSnack('Error: ${e.toString()}', isError: true);
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
          title: Text('unsuspend_user'.tr()),
          content: Text('Are you sure you want to reinstate @$username\'s account?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('cancel'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('unsuspend'.tr(), style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        try {
          await _adminService.unsuspendUser(userId);
          if (mounted) {
            _showSnack('@$username successfully reinstated!');
            _fetchUsers(refresh: true);
            _fetchSuspendedUsers(refresh: true);
          }
        } catch (e) {
          if (mounted) {
            _showSnack('Error: ${e.toString()}', isError: true);
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
              Text('provide_a_clear_reason_for_the'.tr()),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'enter_reason_eg_harassment_spa'.tr().tr(),
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
              child: Text('cancel'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('suspend'.tr(), style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

      if (confirm == true && reasonController.text.trim().isNotEmpty) {
        try {
          await _adminService.suspendUser(userId, reasonController.text.trim());

          if (mounted) {
            _showSnack('@$username suspended successfully.');
            _fetchUsers(refresh: true);
            _fetchSuspendedUsers(refresh: true);
          }
        } catch (e) {
          if (mounted) {
            _showSnack('Error: ${e.toString()}', isError: true);
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
                  labelText: 'reason_for_deletion'.tr(),
                  hintText: 'eg_inappropriate_content_hate'.tr().tr(),
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
            child: Text('cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: Text('delete'.tr(), style: TextStyle(fontWeight: FontWeight.w600)),
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
          _showSnack('Content deleted, warning sent to user, and case resolved.');
          _fetchReports(refresh: true);
          _fetchResolvedReports(refresh: true);
        }
      } catch (e) {
        if (mounted) {
          _showSnack('Error: ${e.toString()}', isError: true);
        }
      }
    }
  }

  void _showDismissReportDialog(String reportId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('dismiss_report'.tr()),
        content: Text('are_you_sure_you_want_to_dismi'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
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
          _showSnack('Report dismissed successfully!');
          _fetchReports(refresh: true);
          _fetchResolvedReports(refresh: true);
        }
      } catch (e) {
        if (mounted) {
          _showSnack('Error: ${e.toString()}', isError: true);
        }
      }
    }
  }

  // --- RENDERING WIDGETS ---

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _surfaceColor(isDarkMode),
      appBar: AppBar(
        title: Text(
          'Admin',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorWeight: 2,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          tabs: [
            Tab(text: 'users'.tr()),
            Tab(text: 'suspended'.tr()),
            Tab(text: 'reports'.tr()),
            Tab(text: 'history'.tr()),
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
              hintText: 'search_user_by_username'.tr().tr(),
              prefixIcon: const Icon(Icons.search, color: Colors.grey),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                onPressed: () {
                  _userSearchController.clear();
                  _fetchUsers(refresh: true);
                },
              ),
              filled: true,
              fillColor: _cardColor(isDarkMode),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _borderColor(isDarkMode)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: _borderColor(isDarkMode)),
              ),
            ),
            onChanged: (val) {
              _fetchUsers(refresh: true);
            },
          ),
        ),

        Expanded(
          child: _users.isEmpty && _usersLoading
              ? Center(child: CircularProgressIndicator())
              : _users.isEmpty
                  ? Center(child: Text('no_users_found'.tr()))
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
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            elevation: 0,
                            color: _cardColor(isDarkMode),
                            shape: _cardShape(isDarkMode),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              leading: ProfileAvatar(userId: userId, username: username, radius: 20),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      username,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (official) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.verified, color: _mutedColor(isDarkMode), size: 16),
                                  ],
                                  if (isSuspended) ...[
                                    const SizedBox(width: 6),
                                    _chip('Suspended', isDarkMode, emphasized: true),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                '$reportsCount report${reportsCount == 1 ? '' : 's'} filed',
                                style: TextStyle(
                                  color: _mutedColor(isDarkMode),
                                  fontSize: 12,
                                  fontWeight: reportsCount > 0 ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: official ? 'remove_badge'.tr() : 'grant_badge'.tr(),
                                    icon: Icon(
                                      official ? Icons.verified : Icons.verified_outlined,
                                      color: _mutedColor(isDarkMode),
                                    ),
                                    onPressed: () => _showOfficialBadgeDialog(userId, username, official),
                                  ),
                                  IconButton(
                                    tooltip: isSuspended ? 'Reinstate' : 'Suspend',
                                    icon: Icon(
                                      isSuspended ? Icons.lock_open_outlined : Icons.lock_outline,
                                      color: _mutedColor(isDarkMode),
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
        ? Center(child: CircularProgressIndicator())
        : _suspendedUsers.isEmpty
            ? Center(child: Text('no_suspended_users_listed'.tr()))
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
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      elevation: 0,
                      color: _cardColor(isDarkMode),
                      shape: _cardShape(isDarkMode),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ProfileAvatar(userId: userId, username: username, radius: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    username,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: () => _showSuspensionDialog(userId, username, isSuspended: true),
                                  style: _adminOutlinedStyle(isDarkMode),
                                  child: Text('reinstate'.tr()),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              reason,
                              style: TextStyle(
                                fontSize: 13,
                                color: _mutedColor(isDarkMode),
                                height: 1.35,
                              ),
                            ),
                          ],
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

    return ReportReasonsWidget(reasons: reasons, isDarkMode: isDarkMode);
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
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _fillColor(isDark),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _borderColor(isDark)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.mic, color: _mutedColor(isDark), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'voice_message'.tr(),
                        style: TextStyle(color: _mutedColor(isDark), fontSize: 13),
                      ),
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
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _fillColor(isDark),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _borderColor(isDark)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, color: _mutedColor(isDark), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'shared_post'.tr(),
                        style: TextStyle(fontSize: 12, color: _mutedColor(isDark)),
                      ),
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
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Media removed · $displayType',
                style: TextStyle(fontSize: 12, color: _mutedColor(isDark)),
              ),
            );
          }
        } else {
          if (cachedAttachmentTypes.isNotEmpty) {
            final displayTypes = cachedAttachmentTypes.join(', ');
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Media removed · $displayTypes',
                style: TextStyle(fontSize: 12, color: _mutedColor(isDark)),
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
            color: isSelected ? _fillColor(isDarkMode) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isSelected
                ? Border.all(color: _borderColor(isDarkMode))
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
      } else if (_selectedReportFilter == 'users') {
        return type == 'user';
      }
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Container(
            decoration: BoxDecoration(
              color: _cardColor(isDarkMode),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor(isDarkMode)),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _buildFilterButton('all', 'All', isDarkMode),
                _buildFilterButton('users', 'Users', isDarkMode),
                _buildFilterButton('posts_comments', 'Posts', isDarkMode),
                _buildFilterButton('chats', 'Chats', isDarkMode),
              ],
            ),
          ),
        ),

        // Main List Content
        Expanded(
          child: _reports.isEmpty && _reportsLoading
              ? Center(child: CircularProgressIndicator())
              : filteredReports.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.grey, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _selectedReportFilter == 'all'
                                ? 'No pending reports.'
                                : 'No reports in this category.',
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
                          } else if (type == 'user') {
                            content = 'Reported User Profile';
                            author = reportData['reportedUserUsername'] as String? ?? 'Anonymous';
                            authorId = reportData['reportedUserId'] as String? ?? '';
                          }

                          return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      elevation: 0,
                      color: _cardColor(isDarkMode),
                      shape: _cardShape(isDarkMode),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    _chip(_typeLabel(type), isDarkMode, emphasized: true),
                                    if (reportCount > 1) ...[
                                      const SizedBox(width: 6),
                                      _chip('$reportCount reports', isDarkMode),
                                    ],
                                  ],
                                ),
                                Text(
                                  date != null ? '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}' : '',
                                  style: TextStyle(color: _mutedColor(isDarkMode), fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _fillColor(isDarkMode),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _borderColor(isDarkMode)),
                              ),
                              child: Text(
                                content != '' ? content : '[Media content]',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode ? Colors.white70 : Colors.black87,
                                  height: 1.4,
                                ),
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
                                          '@$author',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                        ),
                                        const SizedBox(width: 8),
                                        FutureBuilder<DocumentSnapshot>(
                                          future: FirebaseFirestore.instance.collection('users').doc(authorId).get(),
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                                              final userData = snapshot.data!.data() as Map<String, dynamic>?;
                                              final count = userData?['reportsCount'] as int? ?? 0;
                                              return _chip('$count prior reports', isDarkMode);
                                            }
                                            return const SizedBox();
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Reported by @$reporter',
                                      style: TextStyle(color: _mutedColor(isDarkMode), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Divider(height: 24, color: _borderColor(isDarkMode)),

                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _showDismissReportDialog(reportId),
                                  style: _adminOutlinedStyle(isDarkMode),
                                  child: Text('dismiss'.tr()),
                                ),
                                OutlinedButton(
                                    onPressed: () => _showSuspensionDialog(authorId, author),
                                    style: _adminOutlinedStyle(isDarkMode),
                                    child: Text('suspend_author'.tr()),
                                  ),
                                  if (type != 'user')
                                    FilledButton(
                                      onPressed: () => _showDeleteContentDialog(reportDoc),
                                      style: _adminFilledStyle(isDarkMode),
                                      child: Text('delete_content'.tr()),
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
        ? Center(child: CircularProgressIndicator())
        : _resolvedReports.isEmpty
            ? Center(child: Text('no_resolved_reports_history'.tr()))
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
                    } else if (type == 'user') {
                      content = 'Reported User Profile';
                      author = reportData['reportedUserUsername'] as String? ?? 'Anonymous';
                    }

                    final resolutionLabel = resolutionAction == 'deleted'
                        ? 'Content deleted'
                        : resolutionAction == 'dismissed'
                            ? 'status_dismissed'.tr()
                            : 'status_resolved'.tr();

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      elevation: 0,
                      color: _cardColor(isDarkMode),
                      shape: _cardShape(isDarkMode),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    _chip(_typeLabel(type), isDarkMode, emphasized: true),
                                    if (reportCount > 1) ...[
                                      const SizedBox(width: 6),
                                      _chip('$reportCount reports', isDarkMode),
                                    ],
                                  ],
                                ),
                                Text(
                                  date != null ? '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}' : '',
                                  style: TextStyle(color: _mutedColor(isDarkMode), fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _fillColor(isDarkMode),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _borderColor(isDarkMode)),
                              ),
                              child: Text(
                                content != '' ? content : '[Media content]',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode ? Colors.white70 : Colors.black87,
                                  height: 1.4,
                                ),
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
                                      '@$author',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                    Text(
                                      'Reported by @$reporter',
                                      style: TextStyle(color: _mutedColor(isDarkMode), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Divider(height: 24, color: _borderColor(isDarkMode)),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  resolutionLabel,
                                  style: TextStyle(
                                    color: _mutedColor(isDarkMode),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                if (resolvedDate != null)
                                  Text(
                                    '${resolvedDate.day}/${resolvedDate.month} ${resolvedDate.hour}:${resolvedDate.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(color: _mutedColor(isDarkMode), fontSize: 12),
                                  ),
                              ],
                            ),
                            if (reportData['resolutionReason'] != null && (reportData['resolutionReason'] as String).isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _fillColor(isDarkMode),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: _borderColor(isDarkMode)),
                                ),
                                child: Text(
                                  reportData['resolutionReason'] as String,
                                  style: TextStyle(
                                    color: isDarkMode ? Colors.white70 : Colors.black87,
                                    fontSize: 12,
                                    height: 1.35,
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

class ReportReasonsWidget extends StatefulWidget {
  final List<Map<String, String>> reasons;
  final bool isDarkMode;

  const ReportReasonsWidget({
    super.key,
    required this.reasons,
    required this.isDarkMode,
  });

  @override
  State<ReportReasonsWidget> createState() => _ReportReasonsWidgetState();
}

class _ReportReasonsWidgetState extends State<ReportReasonsWidget> {
  bool _expanded = false;

  Color _borderColor(bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300;

  Color _mutedColor(bool isDark) =>
      isDark ? Colors.white60 : Colors.black54;

  Color _fillColor(bool isDark) =>
      isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade100;

  @override
  Widget build(BuildContext context) {
    if (widget.reasons.isEmpty) return const SizedBox.shrink();

    final firstReason = widget.reasons.first;
    final hasMultiple = widget.reasons.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Report reason${hasMultiple ? 's' : ''}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: widget.isDarkMode ? Colors.white70 : Colors.black54,
              ),
            ),
            if (hasMultiple)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _expanded = !_expanded;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _expanded ? Icons.remove : Icons.add,
                        size: 14,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _expanded ? 'Hide' : 'See all (${widget.reasons.length})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        _buildReasonItem(firstReason, hasMultiple && _expanded),
        if (hasMultiple && _expanded)
          ...widget.reasons.skip(1).map((entry) => _buildReasonItem(entry, true)),
      ],
    );
  }

  Widget _buildReasonItem(Map<String, String> entry, bool showUsername) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _fillColor(widget.isDarkMode),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor(widget.isDarkMode)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showUsername)
            Text(
              '@${entry['username']}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _mutedColor(widget.isDarkMode),
              ),
            ),
          if (showUsername) const SizedBox(height: 2),
          Text(
            entry['reason']!,
            style: TextStyle(
              fontSize: 13,
              color: widget.isDarkMode ? Colors.white : Colors.black87,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
