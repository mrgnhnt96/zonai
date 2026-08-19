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
/// Currently `0.4.0` -- the floor two separate pieces of vocabulary both
/// require, which is why it moved once and not twice.
///
/// **Push.** The host enqueues through `EnqueuePushRequest` and expects
/// `MessageHandler`'s push provider to answer it; `0.3.1` has neither, and its
/// internal artifacts declare no `_push_jobs` table and none of the drain or
/// cleanup crons that drive it. A project left on `0.3.x` compiles executables
/// that cannot service a send this CLI will make.
///
/// **OAuth and admin invites.** These add `AuthType.oauth` and
/// `RateLimitOperation.oauthStart` / `.oauthCallback` / `.adminInvite`, all
/// decoded with `Enum.values.byName` (`handlers/rules/rule_request.dart`,
/// `handlers/rate_limits/rate_limit_request.dart`), which throws on a name it
/// does not have. That is the same failure `RateLimitOperation.custom` caused
/// and the reason this floor exists at all.
///
/// The floor first moved to `0.2.0` -- the first release where custom
/// operations work at all, since `0.1.1` ships `DbRateLimits` asserting
/// `request.customOperation!` non-null on a path the host deliberately sets to
/// null, so every custom-operation request 500s before authorization (#27).
///
/// ## The three steps this bump owed, and where they stand
///
/// Raising the floor was never a one-line change; it is the third step of
/// three, and the first two are what make it safe:
///
/// 1. `zonai_schema` goes to `0.4.0` -- adding to an enum consumers switch
///    over exhaustively is breaking before 1.0.
/// 2. **`zonai_client` must be published with a widened constraint.** Its
///    published pubspec declared `zonai_schema: ">=0.1.0 <0.4.0"`, which
///    excludes exactly that release. Widening it in this repo reaches nobody
///    until the client itself is published.
/// 3. Only then raise this floor, and re-run
///    `tool/verify_release_coupling.dart`.
///
/// Step 1 cannot be forgotten: this is a pub workspace, so bumping
/// `zonai_schema` to `0.4.0` while `zonai_client` still says `<0.4.0` fails at
/// `dart pub get` in the repo root, before any test runs --
/// > Because zonai_client depends on zonai_schema >=0.1.0 <0.4.0 and
/// > zonai_workspace depends on zonai_schema, version solving failed.
///
/// (Confirmed by doing it: bumped, resolved, restored.)
///
/// Step 2 is the one that is easy to miss, and it is the half that resolution
/// cannot see. Widening the constraint *here* makes this repo resolve again
/// and reaches no consumer at all -- what bounds them is the constraint on the
/// **published** `zonai_client`. Nothing local reads that.
/// `verify_release_coupling.dart` is the only thing that does, and it asks
/// pub.dev at release time.
const kMinSchemaVersion = '0.4.1';
