import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart' as pc;

/// Top-level function required by compute() — runs PBKDF2 in a background isolate.
Uint8List _runPbkdf2(Map<String, String> args) {
  final password = args['password']!;
  final userId   = args['userId']!;
  final pbkdf2 = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64));
  pbkdf2.init(pc.Pbkdf2Parameters(
    Uint8List.fromList(utf8.encode('asiimov:e2ee:$userId')),
    100000,
    32,
  ));
  return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
}

/// Manages per-user X25519 key pairs for E2EE.
class UserKeyService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _privateKeyStorageKey = 'e2ee_x25519_private_key_v2';
  static const String _publicKeyStorageKey  = 'e2ee_x25519_public_key_v2';
  // Stored in secure storage to persist across app restarts
  static const String _keyTypeStorageKey    = 'e2ee_key_type_v2';
  static const String _keyTypePbkdf2        = 'pbkdf2';

  // In-memory flag: true only when PBKDF2-derived keys are loaded this session
  static bool _isPasswordDerived = false;
  static bool get isPasswordDerived => _isPasswordDerived;

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static final Set<String> _initialized = {};
  static Completer<void>? _initCompleter;

  /// Derives a deterministic X25519 key pair from [password] + [userId].
  ///
  /// PBKDF2-SHA256(password, salt=userId, 100 000 iterations) → 32-byte seed
  /// DartX25519.newKeyPairFromSeed(seed) → deterministic key pair
  ///
  /// The private key is **never transmitted**. Same password always gives the
  /// same key pair on any device — no secure storage required for recovery.
  static Future<void> initFromPassword(String password, String userId) async {
    try {
      late Uint8List seed;

      if (kIsWeb) {
        // Web workers don't support pointycastle — use SHA-256 (instant, pure Dart).
        // Web localStorage is not E2EE-safe anyway; this is a best-effort approach.
        final digest = pc.SHA256Digest();
        seed = digest.process(
            Uint8List.fromList(utf8.encode('asiimov:e2ee:$userId:$password')));
      } else {
        // Mobile/desktop: PBKDF2 (100 000 iterations) in a background isolate.
        seed = await compute(
          _runPbkdf2,
          {'password': password, 'userId': userId},
        );
      }

      // 2. Deterministic X25519 key pair from seed (pure Dart, debug == release)
      final keyPair = await DartX25519().newKeyPairFromSeed(seed);
      final publicKey = await keyPair.extractPublicKey();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

      final pubB64  = base64Encode(publicKey.bytes);
      final privB64 = base64Encode(privateKeyBytes);

      // 3. Cache locally so app restarts reuse these keys without the password
      await _storage.write(key: _privateKeyStorageKey, value: privB64);
      await _storage.write(key: _publicKeyStorageKey,  value: pubB64);
      await _storage.write(key: _keyTypeStorageKey,    value: _keyTypePbkdf2);

      // 4. Publish public key to Firestore (keyType distinguishes pbkdf2 from random)
      await _firestore.collection('users').doc(userId).set({
        'publicKey': pubB64,
        'keyType': 'x25519-pbkdf2',
      }, SetOptions(merge: true));

      _isPasswordDerived = true;
      _initialized.add(userId);
    } catch (e) {
      debugPrint('[E2EE] initFromPassword error: $e');
    }
  }

  /// Initializes E2EE keys for the current user (idempotent).
  /// Concurrent callers all wait for the same in-flight initialization.
  static Future<void> initUserKeys() async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    if (_initialized.contains(userId)) return;

    if (_initCompleter != null) {
      // Another caller already started — wait for it instead of returning early
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();

    try {
      final existingPriv = await _storage.read(key: _privateKeyStorageKey);
      final existingPub = await _storage.read(key: _publicKeyStorageKey);

      if (existingPriv != null && existingPub != null) {
        // Restore in-memory flag if keys were PBKDF2-derived in a previous session
        final storedType = await _storage.read(key: _keyTypeStorageKey);
        if (storedType == _keyTypePbkdf2) _isPasswordDerived = true;

        // Ensure Firestore has the matching public key
        final doc = await _firestore.collection('users').doc(userId).get();
        final firestorePub = doc.data()?['publicKey'] as String?;
        if (firestorePub != existingPub) {
          await _firestore.collection('users').doc(userId).set({
            'publicKey': existingPub,
            'keyType': _isPasswordDerived ? 'x25519-pbkdf2' : 'x25519',
          }, SetOptions(merge: true));
        }
        _initialized.add(userId);
        _initCompleter!.complete();
        return;
      }

      // Generate X25519 key pair — microseconds, no isolate needed
      final algorithm = X25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

      final pubB64 = base64Encode(publicKey.bytes);
      final privB64 = base64Encode(privateKeyBytes);

      // Store locally (never transmitted)
      await _storage.write(key: _privateKeyStorageKey, value: privB64);
      await _storage.write(key: _publicKeyStorageKey, value: pubB64);

      // Use set+merge so it works even if the document/field doesn't exist yet
      await _firestore.collection('users').doc(userId).set({
        'publicKey': pubB64,
        'keyType': 'x25519',
      }, SetOptions(merge: true));

      _initialized.add(userId);
      _initCompleter!.complete();
    } catch (e) {
      debugPrint('E2EE initUserKeys error: $e');
      _initCompleter!.completeError(e);
    } finally {
      _initCompleter = null;
    }
  }

  /// Returns the current user's X25519 key pair from secure storage.
  static Future<SimpleKeyPairData> getMyKeyPair() async {
    var privB64 = await _storage.read(key: _privateKeyStorageKey);
    var pubB64 = await _storage.read(key: _publicKeyStorageKey);

    if (privB64 == null || pubB64 == null) {
      await initUserKeys();
      privB64 = await _storage.read(key: _privateKeyStorageKey);
      pubB64 = await _storage.read(key: _publicKeyStorageKey);
      if (privB64 == null || pubB64 == null) throw Exception('Could not initialize E2EE keys');
    }

    return SimpleKeyPairData(
      base64Decode(privB64),
      publicKey: SimplePublicKey(base64Decode(pubB64), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  /// Fetches a user's PBKDF2-derived X25519 public key from Firestore.
  /// Returns null if the user hasn't logged in with the new E2EE version yet
  /// (keyType != 'x25519-pbkdf2'), which triggers a safe SHA-256 fallback.
  static Future<SimplePublicKey?> getPublicKey(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    final data = doc.data();
    if (data == null) return null;
    final pubB64   = data['publicKey']  as String?;
    final keyType  = data['keyType']    as String?;
    // Only use ECDH when both parties have password-derived keys
    if (pubB64 == null || keyType != 'x25519-pbkdf2') return null;
    try {
      return SimplePublicKey(base64Decode(pubB64), type: KeyPairType.x25519);
    } catch (_) {
      return null;
    }
  }

  /// Wraps [keyBytes] for [recipientPublicKey] using ECIES (X25519 + HKDF + AES-256-GCM).
  /// Returns a JSON string to store in Firestore.
  static Future<String> wrapKeyForRecipient(
    SimplePublicKey recipientPublicKey,
    List<int> keyBytes,
  ) async {
    final x25519 = X25519();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final aesGcm = AesGcm.with256bits();

    // Ephemeral key pair for this wrapping operation
    final ephemeral = await x25519.newKeyPair();
    final ephemeralPub = await ephemeral.extractPublicKey();

    // ECDH shared secret
    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: recipientPublicKey,
    );

    // HKDF to derive AES wrapping key
    final wrappingKey = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: ephemeralPub.bytes, // salt = ephemeral public key
      info: 'conversation-key-wrap'.codeUnits,
    );

    // AES-256-GCM encrypt the conversation key
    final secretBox = await aesGcm.encrypt(keyBytes, secretKey: wrappingKey);

    return jsonEncode({
      'eph': base64Encode(ephemeralPub.bytes),
      'ct': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    });
  }

  /// Unwraps a key previously wrapped by [wrapKeyForRecipient].
  static Future<List<int>> unwrapKey(
    SimpleKeyPairData myKeyPair,
    String wrappedJson,
  ) async {
    final x25519 = X25519();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final aesGcm = AesGcm.with256bits();

    final map = jsonDecode(wrappedJson) as Map<String, dynamic>;
    final ephemeralPubBytes = base64Decode(map['eph'] as String);
    final cipherText = base64Decode(map['ct'] as String);
    final nonce = base64Decode(map['nonce'] as String);
    final mac = base64Decode(map['mac'] as String);

    final ephemeralPub = SimplePublicKey(ephemeralPubBytes, type: KeyPairType.x25519);

    // ECDH shared secret
    final sharedSecret = await x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: ephemeralPub,
    );

    // HKDF to derive the same wrapping key
    final wrappingKey = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: ephemeralPubBytes,
      info: 'conversation-key-wrap'.codeUnits,
    );

    // AES-256-GCM decrypt
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    return await aesGcm.decrypt(secretBox, secretKey: wrappingKey);
  }

  /// Call on logout to reset initialization state.
  static void resetForLogout() {
    _initialized.clear();
    _initCompleter = null;
  }
}
