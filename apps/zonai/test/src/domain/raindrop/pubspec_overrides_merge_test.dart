import 'package:test/test.dart';
import 'package:zonai/src/domain/raindrop/pubspec_overrides_merge.dart';

const _desired = {
  'raindrop': '.zonai/internal/raindrop',
  'raindrop_sqlite': '.zonai/internal/raindrop_sqlite',
};

void main() {
  group('mergePathOverrides', () {
    test('writes a fresh file when input is empty', () {
      final result = mergePathOverrides('', desired: _desired, previouslyOwned: const {});

      expect(result.changed, isTrue);
      expect(result.applied, _desired);
      expect(result.skipped, isEmpty);
      expect(result.content, contains('dependency_overrides:'));
      expect(result.content, contains('.zonai/internal/raindrop'));
      expect(result.content, contains('.zonai/internal/raindrop_sqlite'));
    });

    test('adds dependency_overrides as a new key, preserving other content', () {
      final result = mergePathOverrides(
        '# a comment\nname: whatever\n',
        desired: _desired,
        previouslyOwned: const {},
      );

      expect(result.changed, isTrue);
      expect(result.applied, _desired);
      expect(result.content, contains('# a comment'));
      expect(result.content, contains('name: whatever'));
    });

    test('adds new override keys without touching unrelated existing overrides', () {
      final result = mergePathOverrides(
        'dependency_overrides:\n  something_else:\n    path: ../foo\n',
        desired: _desired,
        previouslyOwned: const {},
      );

      expect(result.changed, isTrue);
      expect(result.applied, _desired);
      expect(result.skipped, isEmpty);
      expect(result.content, contains('something_else:'));
      expect(result.content, contains('../foo'));
    });

    test('refreshes an override it previously owned', () {
      final result = mergePathOverrides(
        'dependency_overrides:\n  raindrop:\n    path: .zonai/internal/raindrop\n',
        desired: const {'raindrop': '.zonai/internal/raindrop-new'},
        previouslyOwned: const {'raindrop': '.zonai/internal/raindrop'},
      );

      expect(result.changed, isTrue);
      expect(result.applied, {'raindrop': '.zonai/internal/raindrop-new'});
      expect(result.skipped, isEmpty);
      expect(result.content, contains('.zonai/internal/raindrop-new'));
    });

    test('is a no-op when the owned override is already correct', () {
      final result = mergePathOverrides(
        'dependency_overrides:\n  raindrop:\n    path: .zonai/internal/raindrop\n',
        desired: const {'raindrop': '.zonai/internal/raindrop'},
        previouslyOwned: const {'raindrop': '.zonai/internal/raindrop'},
      );

      expect(result.changed, isFalse);
      expect(result.applied, {'raindrop': '.zonai/internal/raindrop'});
    });

    test('does not clobber a foreign override for the same package name', () {
      final result = mergePathOverrides(
        'dependency_overrides:\n  raindrop:\n    path: /Users/dev/checkout/raindrop\n',
        desired: const {'raindrop': '.zonai/internal/raindrop'},
        previouslyOwned: const {},
      );

      expect(result.changed, isFalse);
      expect(result.applied, isEmpty);
      expect(result.skipped, {'raindrop': '.zonai/internal/raindrop'});
      expect(result.content, contains('/Users/dev/checkout/raindrop'));
    });

    test('does not clobber a foreign git override for the same package name', () {
      final result = mergePathOverrides(
        'dependency_overrides:\n'
        '  raindrop:\n'
        '    git:\n'
        '      url: https://example.com/raindrop.git\n',
        desired: const {'raindrop': '.zonai/internal/raindrop'},
        previouslyOwned: const {},
      );

      expect(result.changed, isFalse);
      expect(result.skipped, {'raindrop': '.zonai/internal/raindrop'});
      expect(result.content, contains('git:'));
    });

    test('adopts a package once its foreign override has been removed', () {
      // Round 1: a human owns `raindrop`; we don't touch it.
      final round1 = mergePathOverrides(
        'dependency_overrides:\n  raindrop:\n    path: /human/checkout\n',
        desired: const {'raindrop': '.zonai/internal/raindrop'},
        previouslyOwned: const {},
      );
      expect(round1.applied, isEmpty);

      // Round 2: the human override is gone; we adopt the key.
      final round2 = mergePathOverrides(
        '',
        desired: const {'raindrop': '.zonai/internal/raindrop'},
        previouslyOwned: round1.applied,
      );
      expect(round2.applied, {'raindrop': '.zonai/internal/raindrop'});
    });

    test('leaves a malformed (non-map root) file untouched', () {
      final result = mergePathOverrides(
        '- just\n- a\n- list\n',
        desired: _desired,
        previouslyOwned: const {},
      );

      expect(result.changed, isFalse);
      expect(result.applied, isEmpty);
      expect(result.skipped, _desired);
      expect(result.content, '- just\n- a\n- list\n');
    });
  });
}
