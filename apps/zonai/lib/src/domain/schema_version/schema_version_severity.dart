import 'package:pub_semver/pub_semver.dart';

/// How stale a target project's resolved `zonai_schema` is relative to what
/// this CLI build requires.
enum SchemaVersionSeverity {
  /// [resolved] is at least [required] -- nothing to do.
  ok,

  /// [resolved] is older than [required] but still within the same
  /// `^`-compatible range -- the project just hasn't run `pub upgrade` yet.
  warn,

  /// [resolved] falls outside [required]'s own compatible range -- the same
  /// boundary pub itself treats as a breaking change.
  block,
}

/// Mirrors the exact `^`-compatibility semantics of the scaffold's own
/// `zonai_schema: ^$kVersion` constraint (including the pre-1.0 convention
/// where minor, not major, is the breaking slot -- see
/// [Version.nextBreaking]) to decide whether [resolved] falling behind
/// [required] is still "in range" or has crossed a breaking boundary.
SchemaVersionSeverity schemaVersionSeverity({
  required Version resolved,
  required Version required,
}) {
  if (resolved >= required) {
    return SchemaVersionSeverity.ok;
  }

  final sameCohort = VersionConstraint.compatibleWith(resolved).allows(required);
  return sameCohort ? SchemaVersionSeverity.warn : SchemaVersionSeverity.block;
}
