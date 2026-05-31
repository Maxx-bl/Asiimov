import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:firebase_auth/firebase_auth.dart';

import 'encryption_service.dart';
import 'user_key_service.dart';

class PostKeyService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static final Map<String, String> _contentCache = {};
  static final Map<String, enc.Key> _keyCache = {};

  /// Encrypts [content] with a new per-post AES-256 key and distributes it
  /// (ECIES-wrapped) to each user in [visibleTo] + the author.
  static Future<String> encryptPostContent({
    required String postId,
    required String content,
    required List<String> visibleTo,
    required String authorId,
  }) async {
    final postKey = enc.Key.fromSecureRandom(32);
    final encrypted = EncryptionService.encryptWithKey(content, postKey);
    _keyCache[postId] = postKey;
    _contentCache[postId] = content;

    final recipients = {...visibleTo, authorId};
    await _distributePostKey(postId, postKey, recipients);
    return encrypted;
  }

  /// Decrypts [encryptedContent] for the current user.
  /// Returns null if the user doesn't have access or decryption fails.
  static Future<String?> decryptPostContent(String postId, String encryptedContent) async {
    if (_contentCache.containsKey(postId)) return _contentCache[postId];

    final myUserId = _auth.currentUser?.uid;
    if (myUserId == null) return null;

    final encKeyDoc = await _firestore
        .collection('posts')
        .doc(postId)
        .collection('encryptedKeys')
        .doc(myUserId)
        .get();

    if (!encKeyDoc.exists) return null;

    try {
      final wrappedJson = encKeyDoc.data()!['wrappedKey'] as String;
      final myKeyPair = await UserKeyService.getMyKeyPair();
      final keyBytes = await UserKeyService.unwrapKey(myKeyPair, wrappedJson);
      final postKey = enc.Key(Uint8List.fromList(keyBytes));
      _keyCache[postId] = postKey;
      final content = EncryptionService.decryptWithKey(encryptedContent, postKey);
      _contentCache[postId] = content;
      return content;
    } catch (_) {
      return null;
    }
  }

  static void clearCache() {
    _contentCache.clear();
    _keyCache.clear();
  }

  static Future<void> _distributePostKey(
    String postId,
    enc.Key key,
    Set<String> recipientIds,
  ) async {
    final batch = _firestore.batch();
    final keysRef = _firestore.collection('posts').doc(postId).collection('encryptedKeys');

    for (final uid in recipientIds) {
      final publicKey = await UserKeyService.getPublicKey(uid);
      if (publicKey == null) continue;
      final wrapped = await UserKeyService.wrapKeyForRecipient(publicKey, key.bytes);
      batch.set(keysRef.doc(uid), {
        'wrappedKey': wrapped,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }
}
