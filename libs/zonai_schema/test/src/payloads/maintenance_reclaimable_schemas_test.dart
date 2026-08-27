import 'package:test/test.dart';
import 'package:zonai_schema/src/payloads/maintenance_actions.dart';

/// [kReclaimableSchemas] is a hand-written copy of names the engine owns, so
/// the thing worth pinning is that it has not drifted from them.
///
/// It cannot be pinned the way `maintenance_purgeable_tables_test.dart` pins
/// [kPurgeableTableNames]. That test compares the browser-safe copy against
/// `InternalDbArtifacts`, which lives in *this* package, so a VM test can
/// import both sides. The schema names do not: `kLogDbSchema` and
/// `kRateLimitDbSchema` are declared in
/// `apps/zonai/lib/src/domain/constants.dart`, and `apps/zonai` depends on
/// `zonai_schema` rather than the reverse — there is no import that reaches
/// them from here, and adding one would invert the dependency.
///
/// So this pins the half that is available: the literal values, spelled out,
/// and the shape the reclaim path relies on. A change to `kLogDbSchema` in
/// the app fails on the app side, where a matching assertion belongs; a
/// change *here* fails on this side. Both halves are needed, and this file is
/// only one of them — that is stated rather than hidden, because a test that
/// looks like a drift pin while pinning only itself is worse than no test.
void main() {
  test('the reclaimable schemas are the three files zonai attaches', () {
    // Spelled out rather than compared against the constant, so this fails if
    // the constant is edited. `logdb` is `kLogDbSchema` and `ratedb` is
    // `kRateLimitDbSchema`, both in apps/zonai/lib/src/domain/constants.dart.
    expect(kReclaimableSchemas, equals({'main', 'logdb', 'ratedb'}));
  });

  test('main is reclaimable', () {
    // Not implied by the equality above for the reason that matters: this is
    // the member the general reclaim exists for. The affordance used to be
    // log-only, which is how 9.5 MB freed inside `zonai.sqlite` by a
    // `_cron_jobs` purge had no way back to the operating system.
    expect(kReclaimableSchemas, contains('main'));
  });

  test('the log database stays reclaimable', () {
    // The legacy log-only route still has to be expressible as a target of
    // the general one, or generalising the card would drop a working verb.
    expect(kReclaimableSchemas, contains('logdb'));
  });

  test('no schema name is a path', () {
    // The whole point of targeting by schema is that the server never has to
    // decide whether a string from a browser names a file it owns. A member
    // that looked like a path would mean that decision had crept back in.
    for (final schema in kReclaimableSchemas) {
      expect(schema, isNotEmpty);
      expect(schema, isNot(contains('/')));
      expect(schema, isNot(contains('.')));
    }
  });
}
