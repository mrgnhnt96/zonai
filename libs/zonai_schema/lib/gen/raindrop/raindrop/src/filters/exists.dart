// GENERATED CODE - DO NOT MODIFY BY HAND
//
// Vendored from the raindrop/raindrop_sqlite packages (libs/raindrop
// submodule) so zonai_schema has no external path/git dependency on them.
// Baked in with explicit permission from raindrop's original author.
//
// Regenerate: dart run tool/generate_raindrop_vendor.dart

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';

/// `EXISTS (SELECT ...)`, true when [query] matches any row.
///
/// ```dart
/// db.select(users.name).from(users).where(
///       exists(db.select().from(pets).where(users.id.equals(pets.ownerId))),
///     );
/// // WHERE EXISTS (SELECT ... FROM "pets" WHERE "users"."id" = "pets"."ownerId")
/// ```
///
/// For `NOT EXISTS` wrap it with [not]: `not(exists(query))`.
SQL exists(ToQuery<dynamic, dynamic> query) =>
    SQL([const RawSQL('EXISTS'), subquery(query)]);
