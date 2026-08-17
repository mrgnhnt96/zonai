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
/// Nothing enforces the pairing. `tool/verify_release_coupling.dart` only
/// checks that this version is *reachable* by a consumer, which catches the
/// release-ordering mistakes below but says nothing about whether the floor is
/// high enough. A floor left too low fails at the consumer, not here.
///
/// ## Release ordering
///
/// This must never name a version a consumer can't actually resolve, which
/// takes two things: the version is published, and the *published*
/// `zonai_client` allows it (it depends on `zonai_schema`, so its constraint
/// on pub.dev bounds anyone using both, whatever this repo says). The scaffold
/// writes `zonai_schema: ^$kMinSchemaVersion` into new projects, so getting
/// this wrong hands people a pubspec that cannot resolve.
///
/// Order, and the rest of it, in `docs/releasing.md`.
///
/// Currently `0.4.0`: the first release carrying the push vocabulary this CLI
/// dispatches. The host enqueues through `EnqueuePushRequest` and expects
/// `MessageHandler`'s push provider to answer it; `0.3.1` has neither, and its
/// internal artifacts declare no `_push_jobs` table and none of the drain or
/// cleanup crons that drive it. A project left on `0.3.x` therefore compiles
/// executables that cannot service a send this CLI will make.
const kMinSchemaVersion = '0.4.0';
