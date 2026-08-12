/// The oldest `zonai_schema` this CLI can drive.
///
/// Deliberately *not* tied to `kVersion`. The two packages release on their own
/// cadences -- the CLI ships far more often than the schema does -- and tying
/// them together produced a constraint nothing could satisfy: the scaffold
/// asked for `zonai_schema: ^0.6.2` while pub.dev's newest was `0.1.1`, so a
/// fresh project could not `pub get` and every consumer that resolved `0.1.1`
/// was blocked at startup for being "too far behind".
///
/// So this is a floor, not a mirror. A consumer on this version or anything
/// newer is supported; below it, the CLI refuses to run rather than generate
/// code the schema can't honor.
///
/// ## When to raise it
///
/// Raise this in the same change that starts *depending* on something newer --
/// the CLI generating code that calls a schema API added later, or sending an
/// IPC message an older schema can't parse (`RateLimitOperation.custom` was
/// exactly that: a value the host sends and an old worker throws on).
///
/// Nothing enforces the pairing. `verify_min_schema_version.sh` only checks
/// that this version is actually published, which catches the release-ordering
/// mistake below but says nothing about whether the floor is high enough. A
/// floor left too low fails at the consumer, not here.
///
/// ## Release ordering
///
/// This must never name a version that isn't on pub.dev yet: the scaffold
/// writes `zonai_schema: ^$kMinSchemaVersion` into new projects, so a CLI
/// released ahead of its schema hands people a pubspec that cannot resolve.
/// Publish `zonai_schema` first, then release the CLI.
///
/// Currently `0.2.0`: the first release where custom operations work at all.
/// `0.1.1` ships `DbRateLimits` asserting `request.customOperation!` non-null
/// on a path the host deliberately sets to null, so every custom-operation
/// request 500s before authorization (#27).
const kMinSchemaVersion = '0.2.0';
