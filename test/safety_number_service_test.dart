import 'package:asiimov/services/encryption/safety_number_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SafetyNumberService.sortPublicKeys', () {
    test('is order-independent (commutative)', () {
      final a = [1, 2, 3];
      final b = [1, 2, 4];
      final ab = SafetyNumberService.sortPublicKeys(a, b);
      final ba = SafetyNumberService.sortPublicKeys(b, a);
      expect(ab, equals(ba));
      expect(ab.$1, equals(a));
      expect(ab.$2, equals(b));
    });

    test('breaks ties deterministically on equal keys', () {
      final a = [5, 5, 5];
      final b = [5, 5, 5];
      final result = SafetyNumberService.sortPublicKeys(a, b);
      expect(result.$1, equals(a));
      expect(result.$2, equals(b));
    });

    test('handles keys of different lengths deterministically', () {
      final a = [1, 2];
      final b = [1, 2, 3];
      final ab = SafetyNumberService.sortPublicKeys(a, b);
      final ba = SafetyNumberService.sortPublicKeys(b, a);
      expect(ab, equals(ba));
    });
  });

  group('SafetyNumberService.computeSafetyNumber', () {
    test('is identical regardless of argument order', () async {
      final myPub = List<int>.generate(32, (i) => i);
      final theirPub = List<int>.generate(32, (i) => 31 - i);

      final code1 = await SafetyNumberService.computeSafetyNumber(myPub, theirPub);
      final code2 = await SafetyNumberService.computeSafetyNumber(theirPub, myPub);

      expect(code1, equals(code2));
    });

    test('formats as 4 rows of 4 groups of 4 hex chars', () async {
      final myPub = List<int>.generate(32, (i) => i);
      final theirPub = List<int>.generate(32, (i) => 31 - i);

      final code = await SafetyNumberService.computeSafetyNumber(myPub, theirPub);
      final rows = code.split('\n');
      expect(rows.length, equals(4));
      for (final row in rows) {
        final groups = row.split(' ');
        expect(groups.length, equals(4));
        for (final group in groups) {
          expect(group.length, equals(4));
          expect(RegExp(r'^[0-9a-f]{4}$').hasMatch(group), isTrue);
        }
      }
    });

    test('differs when either public key differs', () async {
      final myPub = List<int>.generate(32, (i) => i);
      final theirPub = List<int>.generate(32, (i) => 31 - i);
      final otherPub = List<int>.generate(32, (i) => i + 1);

      final code1 = await SafetyNumberService.computeSafetyNumber(myPub, theirPub);
      final code2 = await SafetyNumberService.computeSafetyNumber(myPub, otherPub);

      expect(code1, isNot(equals(code2)));
    });
  });
}
