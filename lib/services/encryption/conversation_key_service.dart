import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart' as pc;

/// Conversation key derivation — one approach for everything:
///   key = SHA-256( ENCRYPTION_KEY + "_" + chatRoomId )
///
/// Synchronous, zero network calls, identical in debug and release,
/// unique key per conversation.
///
/// The ENCRYPTION_KEY is loaded from Firebase Remote Config at app startup
/// via [setEncryptionKey] — never compiled into the APK.
class ConversationKeyService {
  static final Map<String, enc.Key> _cache = {};
  static String _encryptionKey = '';

  /// Called once at startup after Remote Config is fetched.
  static void setEncryptionKey(String key) {
    if (key == _encryptionKey) return;
    _encryptionKey = key;
    _cache.clear(); // invalidate cached keys when the master key changes
  }

  /// Returns the AES-256 key for [chatRoomId]. Always synchronous.
  static enc.Key getKey({
    required String chatRoomId,
    bool isGroup = false,
    String otherUserId = '',
  }) {
    if (_cache.containsKey(chatRoomId)) return _cache[chatRoomId]!;
    final digest = pc.SHA256Digest();
    final input  = Uint8List.fromList(
        '${_encryptionKey}_$chatRoomId'.codeUnits);
    final key = enc.Key(digest.process(input));
    _cache[chatRoomId] = key;
    return key;
  }

  /// Synchronous cache lookups — for preview decryption.
  static enc.Key? getCachedKey(String chatRoomId) => _cache[chatRoomId];
  static enc.Key? getCachedEcdhKey(String chatRoomId) => _cache[chatRoomId];

  /// Call on logout.
  static void clearAll() => _cache.clear();
}
