// A list of server-side expressions -- the `Schedule.parse(...)`,
// `jwt?.admin.isAdmin`, `RateLimitPolicy(...)` one-liners the reference
// sections show side by side.
//
// A method rather than a top-level list so the fragments can read `jwt`, and a
// list rather than a bare expression because a scaffold has to analyze with an
// empty body too.
import 'package:my_app/src/schemas/items.dart';
import 'package:zonai_schema/zonai_schema.dart';

class Examples {
  Jwt? get jwt => null;
  Item get row => throw UnimplementedError();

  List<Object?> examples() => <Object?>[
    // <<body>>
  ];
}
