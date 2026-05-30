import 'dart:async';
import 'package:flutter/material.dart';

class TypingDots extends StatefulWidget {
  final Color color;
  const TypingDots({super.key, required this.color});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> {
  static const _states = ['.', '..', '...', '..', '.'];
  int _step = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 420), (_) {
      if (mounted) setState(() => _step = (_step + 1) % _states.length);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _states[_step],
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: widget.color,
        letterSpacing: 1.5,
      ),
    );
  }
}
