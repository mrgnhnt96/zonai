import 'package:test/test.dart';
import 'package:zonai/src/domain/versions.dart';

void main() {
  group('isBreakingCliUpgrade', () {
    test('is false for the same version', () {
      expect(isBreakingCliUpgrade(from: '1.2.3', to: '1.2.3'), isFalse);
    });

    test('is false for a patch bump within the same >= 1.0 major', () {
      expect(isBreakingCliUpgrade(from: '1.2.3', to: '1.2.4'), isFalse);
    });

    test('is false for a minor bump within the same >= 1.0 major', () {
      expect(isBreakingCliUpgrade(from: '1.2.3', to: '1.3.0'), isFalse);
    });

    test('is true for a major bump', () {
      expect(isBreakingCliUpgrade(from: '1.9.0', to: '2.0.0'), isTrue);
    });

    test('is false for a patch bump within the same 0.x minor', () {
      expect(isBreakingCliUpgrade(from: '0.6.0', to: '0.6.3'), isFalse);
    });

    test(
      'is true for a minor bump below 1.0, since minor is the breaking slot',
      () {
        expect(isBreakingCliUpgrade(from: '0.6.0', to: '0.7.0'), isTrue);
      },
    );

    test('is true for a downgrade that crosses the same boundary', () {
      expect(isBreakingCliUpgrade(from: '0.7.0', to: '0.6.0'), isTrue);
    });
  });
}
