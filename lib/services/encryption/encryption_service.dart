import 'dart:convert';

import 'package:encrypt/encrypt.dart';

class EncryptionService {
  final Encrypter _encrypter;

  EncryptionService(String keyString)
      : _encrypter = Encrypter(AES(Key.fromUtf8(keyString), mode: AESMode.cbc));

  // ── Instance methods (legacy global key — AES-CBC, kept for old message fallback) ──

  String encrypt(String plainText) {
    if (plainText.isEmpty) return '';
    final iv = IV.fromSecureRandom(16);
    final encrypted = _encrypter.encrypt(plainText, iv: iv);
    return jsonEncode({'iv': iv.base64, 'ciphertext': encrypted.base64});
  }

  String decrypt(String encryptedPayload) {
    if (encryptedPayload.isEmpty) return '';
    final payload = jsonDecode(encryptedPayload) as Map<String, dynamic>;
    final iv = IV.fromBase64(payload['iv'] as String);
    final encrypted = Encrypted.fromBase64(payload['ciphertext'] as String);
    return _encrypter.decrypt(encrypted, iv: iv);
  }

  // ── Static methods (per-conversation / per-post key — AES-256-GCM) ───────────

  /// Encrypts [plainText] with [key] using AES-256-GCM (authenticated encryption).
  /// Format: `{"nonce":"<12-byte nonce b64>","ciphertext":"<ct+16-byte tag b64>"}`
  static String encryptWithKey(String plainText, Key key) {
    if (plainText.isEmpty) return '';
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    // GCM standard: 96-bit (12-byte) nonce
    final nonce = IV.fromSecureRandom(12);
    final encrypted = encrypter.encrypt(plainText, iv: nonce);
    return jsonEncode({'nonce': nonce.base64, 'ciphertext': encrypted.base64});
  }

  /// Decrypts a payload produced by [encryptWithKey].
  /// Auto-detects format: GCM (has "nonce") or legacy CBC (has "iv").
  static String decryptWithKey(String encryptedPayload, Key key) {
    if (encryptedPayload.isEmpty) return '';
    final payload = jsonDecode(encryptedPayload) as Map<String, dynamic>;

    if (payload.containsKey('iv')) {
      // Legacy AES-CBC (messages sent before GCM migration)
      final encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      final iv = IV.fromBase64(payload['iv'] as String);
      final encrypted = Encrypted.fromBase64(payload['ciphertext'] as String);
      return encrypter.decrypt(encrypted, iv: iv);
    }

    // AES-256-GCM
    final encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    final nonce = IV.fromBase64(payload['nonce'] as String);
    final encrypted = Encrypted.fromBase64(payload['ciphertext'] as String);
    return encrypter.decrypt(encrypted, iv: nonce);
  }

  /// Returns true if [value] looks like an encrypted payload (CBC or GCM format).
  static bool isEncrypted(String value) =>
      value.startsWith('{') &&
      value.contains('"ciphertext"') &&
      (value.contains('"iv"') || value.contains('"nonce"'));
}
