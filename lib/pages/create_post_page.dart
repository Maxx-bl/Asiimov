import 'package:asiimov/services/post/post_service.dart';
import 'package:flutter/material.dart';

class CreatePostPage extends StatefulWidget {
  const CreatePostPage({super.key});

  @override
  State<CreatePostPage> createState() => _CreatePostPageState();
}

class _CreatePostPageState extends State<CreatePostPage> {
  final TextEditingController _controller = TextEditingController();
  final int _maxLength = 250;
  bool _isPosting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _post() async {
    if (_controller.text.trim().isEmpty || _isPosting) return;

    setState(() => _isPosting = true);
    // Collapse multiple newlines into a single one to prevent abuse while allowing line breaks
    final cleanContent = _controller.text.trim().replaceAll(RegExp(r'(\r?\n){2,}'), '\n');
    
    try {
      await PostService().createPost(cleanContent);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _isPosting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        foregroundColor: Theme.of(context).colorScheme.primary,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                final isValid =
                    value.text.trim().isNotEmpty && value.text.length <= _maxLength;
                return TextButton(
                  onPressed: isValid && !_isPosting ? _post : null,
                  style: TextButton.styleFrom(
                    backgroundColor:
                        isValid ? Colors.orange : Colors.orange.withValues(alpha: 0.3),
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: _isPosting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Post',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                );
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                maxLength: _maxLength,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: "What's on your mind?",
                  border: InputBorder.none,
                  counterText: '',
                ),
                style: const TextStyle(fontSize: 18),
              ),
            ),

            // Character counter
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                final remaining = _maxLength - value.text.length;
                Color counterColor;
                if (remaining < 0) {
                  counterColor = Colors.red;
                } else if (remaining < 30) {
                  counterColor = Colors.orange;
                } else {
                  counterColor = Colors.grey;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Progress indicator
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          value: (value.text.length / _maxLength).clamp(0, 1),
                          strokeWidth: 2.5,
                          backgroundColor: Colors.grey.shade300,
                          color: remaining < 0
                              ? Colors.red
                              : remaining < 30
                                  ? Colors.orange
                                  : Colors.orange.shade200,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$remaining',
                        style: TextStyle(
                          color: counterColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
