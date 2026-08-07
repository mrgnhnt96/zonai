// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

// ignore_for_file: public_member_api_docs, lines_longer_than_80_chars

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

// ERROR
extension UpdateableX3<V1, V2> on (Updateable<V1>, Updateable<V2>) {
  UpdateableResult<(V1, V2)> get $ {
    return UpdateableResult([this.$1, this.$2]);
  }
}

extension UpdateableX4<V1, V2, V3> on (
  Updateable<V1>,
  Updateable<V2>,
  Updateable<V3>
) {
  UpdateableResult<(V1, V2, V3)> get $ {
    return UpdateableResult([this.$1, this.$2, this.$3]);
  }
}
