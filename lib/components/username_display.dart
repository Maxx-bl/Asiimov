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
  bool? _isVerified;

  @override
  void initState() {
    super.initState();
    _checkVerificationStatus();
  }

  Future<void> _checkVerificationStatus() async {
    if (_verificationCache.containsKey(widget.userId)) {
      if (mounted) {
        setState(() {
          _isVerified = _verificationCache[widget.userId];
        });
      }
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
        
        _verificationCache[widget.userId] = isOfficial;
        
        if (mounted) {
          setState(() {
            _isVerified = isOfficial;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching verification status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isAsiimov = widget.username.toLowerCase() == 'asiimov';
    final defaultStyle = widget.style ?? const TextStyle(fontWeight: FontWeight.bold);
    final appliedStyle = isAsiimov 
        ? defaultStyle.copyWith(color: Colors.blue) 
        : defaultStyle;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '@${widget.username}',
          style: appliedStyle,
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
