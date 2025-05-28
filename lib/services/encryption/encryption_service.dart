import 'package:encrypt/encrypt.dart';
import 'dart:convert';

class EncryptionService {
  final Encrypter _encrypter;

  EncryptionService(String keyString)
      : _encrypter = Encrypter(AES(Key.fromUtf8(keyString), mode: AESMode.cbc));

  String encrypt(String plainText) {
    final iv = IV.fromSecureRandom(16);
    final encrypted = _encrypter.encrypt(plainText, iv: iv);

    final payload = {
      'iv': iv.base64,
      'ciphertext': encrypted.base64,
    };

    return jsonEncode(payload);
  }

  String decrypt(String encryptedPayload) {
    final Map<String, dynamic> payload = jsonDecode(encryptedPayload);
    final iv = IV.fromBase64(payload['iv']);
    final encrypted = Encrypted.fromBase64(payload['ciphertext']);

    return _encrypter.decrypt(encrypted, iv: iv);
  }
}
