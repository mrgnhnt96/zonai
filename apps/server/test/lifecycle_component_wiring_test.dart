import 'package:revali_router/revali_router.dart';
import 'package:test/test.dart';

import '../routes/components/black_list.dart';

/// Guards only run if their annotation class is *typed* as a
/// [LifecycleComponent].
///
/// This is a whole test file for one `implements` clause because of how it
/// fails. Revali's server generator decides an annotation contributes a guard
/// by matching its static type against that marker
/// (`ServerRouteAnnotations._fromGetter`, `classType: LifecycleComponent`).
/// Drop the clause and nothing complains: `@BlackList()` still compiles, the
/// class still has a correct `check` method, codegen still succeeds, every
/// test still passes — and the annotation silently contributes nothing, so
/// every controller carrying it serves unguarded.
///
/// That is not hypothetical. It is known-issues.md #1, where exactly this
/// left sign-in, sign-up, refresh, reset-password and the whole CRUD surface
/// with no IP-based abuse protection at all, undetected, because the only
/// evidence is an absence in generated output nobody reads.
///
/// What this does *not* cover: that a blacklisted IP is actually rejected at
/// runtime. That needs a live server and a seeded `abusers` row. This pins
/// the one property whose loss is invisible.
void main() {
  test('BlackList is typed as a LifecycleComponent, so it is generated as a '
      'guard', () {
    expect(
      const BlackList(),
      isA<LifecycleComponent>(),
      reason:
          'without this the annotation is inert and every @BlackList() '
          'controller is unprotected -- see known-issues.md #1',
    );
  });
}
