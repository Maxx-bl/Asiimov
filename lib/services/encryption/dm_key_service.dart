import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:encrypt/encrypt.dart' as enc;

import 'safety_number_service.dart';
import 'user_key_service.dart';

/// Derives the real end-to-end key for a 1:1 conversation via static-static
/// X25519 ECDH between the two participants' identity keys, instead of the
/// server-controlled shared secret used by [ConversationKeyService]. Both
/// sides compute the same key locally — nothing is transmitted or stored.
class DmKeyService {
  static final Map<String, enc.Key> _cache = {};
  static final Map<String, Future<enc.Key?>> _inFlight = {};

  /// Returns the ECDH-derived AES-256 key for [chatRoomId], or null if the
  /// other participant hasn't published a password-derived X25519 key yet
  /// (caller should fall back to the legacy scheme in that case).
  static Future<enc.Key?> getKey({
    required String chatRoomId,
    required String otherUid,
  }) {
    final cached = _cache[chatRoomId];
    if (cached != null) return Future.value(cached);

    final inFlight = _inFlight[chatRoomId];
    if (inFlight != null) return inFlight;

    final future = _computeKey(chatRoomId, otherUid);
    _inFlight[chatRoomId] = future;
    future.whenComplete(() => _inFlight.remove(chatRoomId));
    return future;
  }

  static Future<enc.Key?> _computeKey(String chatRoomId, String otherUid) async {
    try {
      // UserKeyService.getPublicKey(otherUid) only checks THEIR keyType.
      // My own key must also be password-derived (stable across reinstalls)
      // — otherwise I could successfully derive a key here (because the
      // other side qualifies) while they can never re-derive the same key
      // from their side (because my keyType isn't 'x25519-pbkdf2' yet),
      // permanently bricking decryption for them. Both sides must agree.
      if (!UserKeyService.isPasswordDerived) return null;

      final theirPub = await UserKeyService.getPublicKey(otherUid);
      if (theirPub == null) return null;

      final myKeyPair = await UserKeyService.getMyKeyPair();
      final myPub = myKeyPair.publicKey.bytes;

      final sharedSecret = await X25519().sharedSecretKey(
        keyPair: myKeyPair,
        remotePublicKey: theirPub,
      );

      final (first, second) =
          SafetyNumberService.sortPublicKeys(myPub, theirPub.bytes);
      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
      final derived = await hkdf.deriveKey(
        secretKey: sharedSecret,
        nonce: Uint8List.fromList([...first, ...second]),
        info: utf8.encode('asiimov-dm-key-v1'),
      );

      final keyBytes = await derived.extractBytes();
      final key = enc.Key(Uint8List.fromList(keyBytes));
      _cache[chatRoomId] = key;
      return key;
    } catch (_) {
      return null;
    }
  }

  /// Synchronous cache lookup only — for preview-decryption paths that
  /// cannot await. Returns null on a cache miss (caller keeps its fallback
  /// and this populates the cache in the background via [getKey]).
  static enc.Key? getCachedKey(String chatRoomId) => _cache[chatRoomId];

  /// Call on logout.
  static void clearAll() {
    _cache.clear();
    _inFlight.clear();
  }
}
