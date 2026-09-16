// Exercises the same X25519 ECDH + HKDF derivation DmKeyService performs,
// without going through UserKeyService (which needs FirebaseAuth/Firestore/
// secure storage) — verifies both participants derive an identical key.
import 'dart:convert';
import 'dart:typed_data';

import 'package:asiimov/services/encryption/safety_number_service.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<int>> _deriveDmKey(
  SimpleKeyPairData myKeyPair,
  SimplePublicKey theirPub,
) async {
  final sharedSecret = await X25519().sharedSecretKey(
    keyPair: myKeyPair,
    remotePublicKey: theirPub,
  );
  final myPub = myKeyPair.publicKey.bytes;
  final (first, second) = SafetyNumberService.sortPublicKeys(myPub, theirPub.bytes);
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final derived = await hkdf.deriveKey(
    secretKey: sharedSecret,
    nonce: Uint8List.fromList([...first, ...second]),
    info: utf8.encode('asiimov-dm-key-v1'),
  );
  return derived.extractBytes();
}

void main() {
  Future<SimpleKeyPairData> materialize(SimpleKeyPair keyPair) async {
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pub = await keyPair.extractPublicKey();
    return SimpleKeyPairData(privBytes, publicKey: pub, type: KeyPairType.x25519);
  }

  test('both participants derive the same DM key from static-static ECDH', () async {
    final aliceKeyPair = await materialize(await X25519().newKeyPair());
    final bobKeyPair = await materialize(await X25519().newKeyPair());

    final keyFromAlice = await _deriveDmKey(aliceKeyPair, bobKeyPair.publicKey);
    final keyFromBob = await _deriveDmKey(bobKeyPair, aliceKeyPair.publicKey);

    expect(keyFromAlice, equals(keyFromBob));
    expect(keyFromAlice.length, equals(32));
  });

  test('different key pairs derive different DM keys', () async {
    final aliceKeyPair = await materialize(await X25519().newKeyPair());
    final bobKeyPair = await materialize(await X25519().newKeyPair());
    final carolKeyPair = await materialize(await X25519().newKeyPair());

    final keyWithBob = await _deriveDmKey(aliceKeyPair, bobKeyPair.publicKey);
    final keyWithCarol = await _deriveDmKey(aliceKeyPair, carolKeyPair.publicKey);

    expect(keyWithBob, isNot(equals(keyWithCarol)));
  });
}
