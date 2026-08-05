import 'package:test/test.dart';
import 'package:zonai/src/domain/schema_version/pubspec_lock_parser.dart';

void main() {
  group('resolvedPackageVersion', () {
    test('returns PackageNotFound for empty content', () {
      final result = resolvedPackageVersion('', packageName: 'zonai_schema');
      expect(result, isA<PackageNotFound>());
    });

    test('returns PackageNotFound for whitespace-only content', () {
      final result = resolvedPackageVersion('   \n', packageName: 'zonai_schema');
      expect(result, isA<PackageNotFound>());
    });

    test('returns UnresolvableVersion for a non-map root', () {
      final result = resolvedPackageVersion(
        '- just\n- a\n- list\n',
        packageName: 'zonai_schema',
      );
      expect(result, isA<UnresolvableVersion>());
    });

    test('returns PackageNotFound when packages: is missing entirely', () {
      final result = resolvedPackageVersion('sdks:\n  dart: ">=3.0.0"\n', packageName: 'zonai_schema');
      expect(result, isA<PackageNotFound>());
    });

    test('returns PackageNotFound when the package is absent', () {
      final result = resolvedPackageVersion(
        'packages:\n  some_other_package:\n    source: hosted\n    version: "1.0.0"\n',
        packageName: 'zonai_schema',
      );
      expect(result, isA<PackageNotFound>());
    });

    test('returns UnresolvableVersion for a path-sourced entry with no version key '
        '(the actual shape zonai_schema has in every fixture in this repo today)', () {
      final result = resolvedPackageVersion(
        'packages:\n'
        '  zonai_schema:\n'
        '    dependency: "direct main"\n'
        '    description:\n'
        '      path: "../../libs/zonai_schema"\n'
        '      relative: true\n'
        '    source: path\n',
        packageName: 'zonai_schema',
      );
      expect(result, isA<UnresolvableVersion>());
    });

    test('returns UnresolvableVersion for a git-sourced entry', () {
      final result = resolvedPackageVersion(
        'packages:\n'
        '  zonai_schema:\n'
        '    source: git\n'
        '    version: "1.2.3"\n',
        packageName: 'zonai_schema',
      );
      expect(result, isA<UnresolvableVersion>());
    });

    test('returns ResolvedVersion for a valid hosted entry', () {
      final result = resolvedPackageVersion(
        'packages:\n'
        '  zonai_schema:\n'
        '    dependency: "direct main"\n'
        '    source: hosted\n'
        '    version: "0.5.1"\n',
        packageName: 'zonai_schema',
      );
      expect(result, isA<ResolvedVersion>());
      expect((result as ResolvedVersion).version.toString(), '0.5.1');
    });

    test('returns UnresolvableVersion for hosted with a missing version key', () {
      final result = resolvedPackageVersion(
        'packages:\n  zonai_schema:\n    source: hosted\n',
        packageName: 'zonai_schema',
      );
      expect(result, isA<UnresolvableVersion>());
    });

    test('returns UnresolvableVersion for hosted with an unparsable version', () {
      final result = resolvedPackageVersion(
        'packages:\n  zonai_schema:\n    source: hosted\n    version: "not-a-version"\n',
        packageName: 'zonai_schema',
      );
      expect(result, isA<UnresolvableVersion>());
    });
  });
}
