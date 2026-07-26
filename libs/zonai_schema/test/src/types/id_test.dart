import 'package:test/test.dart';
import 'package:zonai_schema/zonai_schema.dart';

/// Builds [value] at runtime, not compile time — a `const UnknownId('x')`
/// literal gets canonicalized by the compiler, so two separately-written
/// `const` instances with the same value are already `identical()` before
/// any operator== even runs, masking exactly the bug these tests exist to
/// catch. Every instance below is built through this so equality is
/// actually exercised, not accidentally satisfied by const-folding.
String _runtimeValue(String value) => [value].join();

void main() {
  group('UnknownId equality', () {
    // `implements Id` only takes on Id's member *signatures*, not its
    // concrete operator==/hashCode bodies (Dart doesn't inherit
    // implementations through `implements`) — so two UnknownIds built from
    // the same string down separate paths (e.g. a JWT's decoded userId vs.
    // an ownerId column read back from a row) used to compare unequal. This
    // silently broke every ownership check built on `jwt.userId ==
    // row.ownerId` (PhotoRowRules.canUpdate/canDelete included), always
    // denying the real owner. See id.dart's UnknownId doc comment.
    test('two UnknownIds built from the same value are equal', () {
      final a = UnknownId(_runtimeValue('user_123'));
      final b = UnknownId(_runtimeValue('user_123'));
      expect(identical(a, b), isFalse, reason: 'sanity check: must be distinct instances');
      expect(a, b);
    });

    test('two UnknownIds built from different values are not equal', () {
      expect(
        UnknownId(_runtimeValue('user_123')),
        isNot(UnknownId(_runtimeValue('user_456'))),
      );
    });

    test('hashCode matches for equal UnknownIds (Set/Map correctness)', () {
      expect(
        UnknownId(_runtimeValue('user_123')).hashCode,
        UnknownId(_runtimeValue('user_123')).hashCode,
      );
    });

    test('an UnknownId is comparable to any other Id subtype with the same value', () {
      // PhotoId requires its value to end with its 'ph' suffix.
      // ignore: unrelated_type_equality_checks
      expect(
        UnknownId(_runtimeValue('abc_ph')) == PhotoId(_runtimeValue('abc_ph')),
        isTrue,
      );
    });
  });
}
