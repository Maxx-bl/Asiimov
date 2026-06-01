import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:firebase_auth/firebase_auth.dart';

import 'user_key_service.dart';

class ConversationKeyService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // In-memory cache for ECIES distributed keys: chatRoomId → {key, version}
  static final Map<String, enc.Key> _keyCache = {};
  static final Map<String, int> _keyVersionCache = {};

  // Separate cache for ECDH-derived keys (never mixed with ECIES keys)
  static final Map<String, enc.Key> _ecdhKeyCache = {};

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

  /// Derives a stable key for a **group** chat from all members' public keys.
  ///
  /// key_material = SHA-256( sorted(all_member_pub_keys concatenated) )
  /// group_key    = HKDF-SHA256( key_material, info="group-key:<chatRoomId>" )
  ///
  /// Every member independently computes the same key — no distribution, no
  /// race conditions. The key changes automatically when membership changes.
  static Future<enc.Key?> getDerivedGroupChatKey(
    String chatRoomId,
    List<String> memberIds,
  ) async {
    if (_ecdhKeyCache.containsKey(chatRoomId)) return _ecdhKeyCache[chatRoomId];

    try {
      await UserKeyService.initUserKeys();

      final sortedIds = List<String>.from(memberIds)..sort();
      final List<int> combined = [];
      for (final uid in sortedIds) {
        final pubKey = await UserKeyService.getPublicKey(uid);
        if (pubKey == null) return null; // member has no key yet — retry later
        combined.addAll(pubKey.bytes);
      }

      // Hash the combined material so HKDF has a fixed-size input
      final sha256 = Sha256();
      final hash = await sha256.hash(combined);

      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
      final derived = await hkdf.deriveKey(
        secretKey: SecretKey(hash.bytes),
        info: utf8.encode('group-key:$chatRoomId'),
      );

      final keyBytes = await derived.extractBytes();
      final key = enc.Key(Uint8List.fromList(keyBytes));
      _ecdhKeyCache[chatRoomId] = key;
      return key;
    } catch (_) {
      return null;
    }
  }

  /// Derives a stable conversation key for a **private** chat via X25519 ECDH.
  ///
  /// Both parties independently compute:
  ///   sharedSecret = X25519(myPrivateKey, otherPublicKey)
  /// and then:
  ///   conversationKey = HKDF-SHA256(sharedSecret, info="chat-key:<chatRoomId>")
  ///
  /// By the ECDH property both sides always get the same key — no Firestore
  /// distribution, no race conditions, no rotation loops.
  static Future<enc.Key?> getDerivedPrivateChatKey(
    String chatRoomId,
    String otherUserId,
  ) async {
    // Use a dedicated cache — never mixed with ECIES keys from getOrCreateConversationKey
    if (_ecdhKeyCache.containsKey(chatRoomId)) return _ecdhKeyCache[chatRoomId];

    try {
      await UserKeyService.initUserKeys();
      final myKeyPair = await UserKeyService.getMyKeyPair();
      final otherPublicKey = await UserKeyService.getPublicKey(otherUserId);
      if (otherPublicKey == null) return null; // other user hasn't set up E2EE yet

      final x25519 = X25519();
      final sharedSecret = await x25519.sharedSecretKey(
        keyPair: myKeyPair,
        remotePublicKey: otherPublicKey,
      );

      final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
      final derived = await hkdf.deriveKey(
        secretKey: sharedSecret,
        info: utf8.encode('chat-key:$chatRoomId'),
      );

      final keyBytes = await derived.extractBytes();
      final key = enc.Key(Uint8List.fromList(keyBytes));
      _ecdhKeyCache[chatRoomId] = key;
      return key;
    } catch (_) {
      return null;
    }
  }

  /// Returns the cached ECIES key for [chatRoomId], or null if not yet loaded.
  static enc.Key? getCachedKey(String chatRoomId) => _keyCache[chatRoomId];

  /// Returns the cached ECDH-derived key for [chatRoomId], or null if not yet loaded.
  static enc.Key? getCachedEcdhKey(String chatRoomId) => _ecdhKeyCache[chatRoomId];

  /// Checks if the conversation key has been rotated (Firestore version changed)
  /// and refreshes the cache if so. Never generates new keys.
  /// Safe to call on every received message.
  static Future<enc.Key?> refreshKeyIfExists(String chatRoomId) async {
    final myUserId = _auth.currentUser?.uid;
    if (myUserId == null) return null;

    try {
      final doc = await _firestore
          .collection('chats')
          .doc(chatRoomId)
          .collection('encryptedKeys')
          .doc(myUserId)
          .get();

      if (!doc.exists) return _keyCache[chatRoomId]; // no document → keep cached

      final data = doc.data()!;
      final firestoreVersion = (data['version'] as int?) ?? 1;

      if (_keyCache.containsKey(chatRoomId) &&
          _keyVersionCache[chatRoomId] == firestoreVersion) {
        return _keyCache[chatRoomId]; // version unchanged → return cached
      }

      // Version changed (key rotation) — unwrap and cache new key
      final wrappedJson = data['wrappedKey'] as String;
      final myKeyPair = await UserKeyService.getMyKeyPair();
      final keyBytes = await UserKeyService.unwrapKey(myKeyPair, wrappedJson);
      final key = enc.Key(Uint8List.fromList(keyBytes));
      _keyCache[chatRoomId] = key;
      _keyVersionCache[chatRoomId] = firestoreVersion;
      return key;
    } catch (_) {
      return _keyCache[chatRoomId]; // on error keep whatever is cached
    }
  }

  /// Fetches the key from Firestore if it exists and caches it.
  /// Does NOT generate a new key — safe to call for preview/read-only contexts.
  static Future<enc.Key?> fetchKeyIfExists(String chatRoomId) async {
    if (_keyCache.containsKey(chatRoomId)) return _keyCache[chatRoomId];

    final myUserId = _auth.currentUser?.uid;
    if (myUserId == null) return null;

    try {
      final doc = await _firestore
          .collection('chats')
          .doc(chatRoomId)
          .collection('encryptedKeys')
          .doc(myUserId)
          .get();

      if (!doc.exists) return null;

      final data = doc.data()!;
      final wrappedJson = data['wrappedKey'] as String;
      final myKeyPair = await UserKeyService.getMyKeyPair();
      final keyBytes = await UserKeyService.unwrapKey(myKeyPair, wrappedJson);
      final key = enc.Key(Uint8List.fromList(keyBytes));
      _keyCache[chatRoomId] = key;
      _keyVersionCache[chatRoomId] = (data['version'] as int?) ?? 1;
      return key;
    } catch (_) {
      return null;
    }
  }

  /// Clears all cached keys (call on logout).
  static void clearAll() {
    _keyCache.clear();
    _keyVersionCache.clear();
    _ecdhKeyCache.clear();
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
