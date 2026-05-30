import 'package:shared_preferences/shared_preferences.dart';

class DraftService {
  static const String _keyPrefix = 'draft_';

  static final Map<String, String> _cache = {};
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Reload all saved drafts into the in-memory cache
    for (final key in _prefs!.getKeys()) {
      if (key.startsWith(_keyPrefix)) {
        final conversationId = key.substring(_keyPrefix.length);
        final value = _prefs!.getString(key);
        if (value != null && value.isNotEmpty) {
          _cache[conversationId] = value;
        }
      }
    }
  }

  static void save(String conversationId, String text) {
    if (text.isEmpty) {
      _cache.remove(conversationId);
      _prefs?.remove('$_keyPrefix$conversationId');
    } else {
      _cache[conversationId] = text;
      _prefs?.setString('$_keyPrefix$conversationId', text);
    }
  }

  static String? get(String conversationId) => _cache[conversationId];

  static void clear(String conversationId) {
    _cache.remove(conversationId);
    _prefs?.remove('$_keyPrefix$conversationId');
  }
}
