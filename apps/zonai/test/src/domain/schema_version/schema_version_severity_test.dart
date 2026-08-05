import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:zonai/src/domain/schema_version/schema_version_severity.dart';

void main() {
  group('schemaVersionSeverity', () {
    test('is ok when resolved equals required', () {
      final severity = schemaVersionSeverity(
        resolved: Version.parse('1.2.3'),
        required: Version.parse('1.2.3'),
      );
      expect(severity, SchemaVersionSeverity.ok);
    });

    test('is ok when resolved is newer than required', () {
      final severity = schemaVersionSeverity(
        resolved: Version.parse('1.3.0'),
        required: Version.parse('1.2.3'),
      );
      expect(severity, SchemaVersionSeverity.ok);
    });

    test('is warn when resolved is older but in the same compatible cohort (>= 1.0)', () {
      final severity = schemaVersionSeverity(
        resolved: Version.parse('1.2.0'),
        required: Version.parse('1.2.3'),
      );
      expect(severity, SchemaVersionSeverity.warn);
    });

    test('is block when resolved falls outside the compatible cohort (>= 1.0)', () {
      // 1.1.9 and 1.2.3 share major 1, so that's actually still same-cohort
      // (warn) under real `^` semantics -- a genuine cross-major gap is what
      // crosses the breaking boundary post-1.0.
      final severity = schemaVersionSeverity(
        resolved: Version.parse('1.9.0'),
        required: Version.parse('2.0.0'),
      );
      expect(severity, SchemaVersionSeverity.block);
    });

    test('is warn when resolved is an older patch in the same 0.x minor cohort', () {
      final severity = schemaVersionSeverity(
        resolved: Version.parse('0.5.0'),
        required: Version.parse('0.5.3'),
      );
      expect(severity, SchemaVersionSeverity.warn);
    });

    test('is block on a 0.x minor gap, since minor is the breaking slot below 1.0', () {
      final severity = schemaVersionSeverity(
        resolved: Version.parse('0.4.9'),
        required: Version.parse('0.5.0'),
      );
      expect(severity, SchemaVersionSeverity.block);
    });
  });
}
