// The hook signature *listings* -- the tables of `Future<void> beforeCreate(T
// object, Jwt? jwt)` lines the docs use to introduce a hook family.
//
// Redeclaring them against `Extension<T>` is what makes the listing checkable:
// a signature that drifts from the real hook fails as an invalid override,
// which is the drift these listings are most likely to carry. The doc writes
// them with a trailing `;` so they are declarations rather than prose.
import 'package:zonai_schema/zonai_schema.dart';

abstract class DocumentedHooks<T> extends Extension<T> {
  DocumentedHooks(super.schema);

  // <<body>>
}
