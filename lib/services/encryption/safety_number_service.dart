import 'package:cryptography/cryptography.dart';

/// Deterministic ordering + hashing of two X25519 public keys, shared by
/// [SafetyNumberService] (human-verifiable code) and `DmKeyService` (HKDF
/// salt for the message key) so both derive the same value regardless of
/// which side computes it first.
class SafetyNumberService {
  /// Lexicographically orders [a] and [b] so both parties get an identical
  /// (first, second) pair no matter who is "me" and who is "them".
  static (List<int> first, List<int> second) sortPublicKeys(
    List<int> a,
    List<int> b,
  ) {
    final len = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      if (a[i] != b[i]) {
        return a[i] < b[i] ? (a, b) : (b, a);
      }
    }
    // Equal keys (should never happen for two distinct accounts) or one is
    // a prefix of the other — fall back to length as a deterministic
    // tie-breaker so the result is still well-defined.
    return a.length <= b.length ? (a, b) : (b, a);
  }

  /// Returns SHA-256(sorted(pubA || pubB)) formatted as 4 rows of 4 groups
  /// of 4 hex chars, for display and manual out-of-band comparison.
  static Future<String> computeSafetyNumber(
    List<int> myPub,
    List<int> theirPub,
  ) async {
    final (first, second) = sortPublicKeys(myPub, theirPub);
    final hash = await Sha256().hash([...first, ...second]);
    final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final groups = List.generate(16, (i) => hex.substring(i * 4, i * 4 + 4));
    final rows = List.generate(4, (r) => groups.sublist(r * 4, r * 4 + 4).join(' '));
    return rows.join('\n');
  }
}
