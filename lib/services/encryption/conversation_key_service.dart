import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:firebase_auth/firebase_auth.dart';

import 'user_key_service.dart';

class ConversationKeyService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // In-memory cache: chatRoomId → {key, version}
  static final Map<String, enc.Key> _keyCache = {};
  static final Map<String, int> _keyVersionCache = {};

  /// Returns (or creates) the AES-256 conversation key for [chatRoomId].
  static Future<enc.Key> getOrCreateConversationKey(
    String chatRoomId,
    List<String> participantIds,
  ) async {
    final myUserId = _auth.currentUser!.uid;

    final encryptedKeyDoc = await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('encryptedKeys')
        .doc(myUserId)
        .get();

    if (encryptedKeyDoc.exists) {
      final data = encryptedKeyDoc.data()!;
      final firestoreVersion = (data['version'] as int?) ?? 1;

      // Return cached key if version hasn't changed
      if (_keyCache.containsKey(chatRoomId) &&
          _keyVersionCache[chatRoomId] == firestoreVersion) {
        return _keyCache[chatRoomId]!;
      }

      try {
        final wrappedJson = data['wrappedKey'] as String;
        final myKeyPair = await UserKeyService.getMyKeyPair();
        final keyBytes = await UserKeyService.unwrapKey(myKeyPair, wrappedJson);
        final key = enc.Key(Uint8List.fromList(keyBytes));
        _keyCache[chatRoomId] = key;
        _keyVersionCache[chatRoomId] = firestoreVersion;
        return key;
      } catch (_) {
        // Key was wrapped for a different key pair (e.g. new device or browser session).
        // Fall through to generate and redistribute a new conversation key so this
        // device can send and receive going forward. Old messages will be unreadable,
        // but that is already the case when the private key is lost.
        _keyCache.remove(chatRoomId);
        _keyVersionCache.remove(chatRoomId);
      }
    }

    // No key yet (or old key unreadable) — generate and distribute to all participants
    final newVersion = (_keyVersionCache[chatRoomId] ?? 0) + 1;
    final newKey = enc.Key.fromSecureRandom(32);
    await _distributeKey(chatRoomId, participantIds, newKey, version: newVersion);
    _keyCache[chatRoomId] = newKey;
    _keyVersionCache[chatRoomId] = newVersion;
    return newKey;
  }

  /// Distributes [conversationKey] to [newUserId] (e.g. new group member).
  static Future<void> addParticipant(
    String chatRoomId,
    String newUserId,
    enc.Key conversationKey,
  ) async {
    final publicKey = await UserKeyService.getPublicKey(newUserId);
    if (publicKey == null) return;

    // Fetch current version so the new participant's doc has the right version
    int currentVersion = 1;
    try {
      final myUserId = _auth.currentUser!.uid;
      final existingDoc = await _firestore
          .collection('chats')
          .doc(chatRoomId)
          .collection('encryptedKeys')
          .doc(myUserId)
          .get();
      currentVersion = (existingDoc.data()?['version'] as int?) ?? 1;
    } catch (_) {}

    final wrapped = await UserKeyService.wrapKeyForRecipient(publicKey, conversationKey.bytes);
    await _firestore
        .collection('chats')
        .doc(chatRoomId)
        .collection('encryptedKeys')
        .doc(newUserId)
        .set({
      'wrappedKey': wrapped,
      'version': currentVersion,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Returns the cached key for [chatRoomId], or null if not yet loaded.
  static enc.Key? getCachedKey(String chatRoomId) => _keyCache[chatRoomId];

  /// Clears all cached keys (call on logout).
  static void clearAll() {
    _keyCache.clear();
    _keyVersionCache.clear();
  }

  // ── Private ──────────────────────────────────────────────────────────────────

  static Future<void> _distributeKey(
    String chatRoomId,
    List<String> participantIds,
    enc.Key key, {
    int version = 1,
  }) async {
    final batch = _firestore.batch();
    final keysRef =
        _firestore.collection('chats').doc(chatRoomId).collection('encryptedKeys');

    for (final uid in participantIds) {
      final publicKey = await UserKeyService.getPublicKey(uid);
      if (publicKey == null) continue;

      final wrapped = await UserKeyService.wrapKeyForRecipient(publicKey, key.bytes);
      batch.set(keysRef.doc(uid), {
        'wrappedKey': wrapped,
        'version': version,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }
}
