import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UsernameDisplay extends StatefulWidget {
  final String userId;
  final String username;
  final TextStyle? style;
  final double iconSize;

  const UsernameDisplay({
    super.key,
    required this.userId,
    required this.username,
    this.style,
    this.iconSize = 14.0,
  });

  @override
  State<UsernameDisplay> createState() => _UsernameDisplayState();
}

class _UsernameDisplayState extends State<UsernameDisplay> {
  static final Map<String, bool> _verificationCache = {};
  static final Map<String, String> _usernameCache = {};
  bool? _isVerified;
  String? _username;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void didUpdateWidget(covariant UsernameDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId || oldWidget.username != widget.username) {
      _initData();
    }
  }

  void _initData() {
    _username = widget.username.isNotEmpty ? widget.username : _usernameCache[widget.userId];
    _isVerified = _verificationCache[widget.userId];
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    if (_verificationCache.containsKey(widget.userId) && 
        (widget.username.isNotEmpty || _usernameCache.containsKey(widget.userId))) {
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final bool isOfficial = data['official'] == true;
        final String fetchedUsername = data['username'] ?? "Unknown";
        
        _verificationCache[widget.userId] = isOfficial;
        _usernameCache[widget.userId] = fetchedUsername;
        
        if (mounted) {
          setState(() {
            _isVerified = isOfficial;
            _username = fetchedUsername;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUsername = _username ?? widget.username;
    final bool isAsiimov = currentUsername.toLowerCase() == 'asiimov';
    final defaultStyle = widget.style ?? const TextStyle(fontWeight: FontWeight.bold);
    final appliedStyle = isAsiimov 
        ? defaultStyle.copyWith(color: Colors.blue) 
        : defaultStyle;

    if (currentUsername.isEmpty) {
      return const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(strokeWidth: 1),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '@$currentUsername',
            style: appliedStyle,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        if (_isVerified == true) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.verified,
            color: Colors.blue,
            size: widget.iconSize,
          ),
        ],
      ],
    );
  }
}
