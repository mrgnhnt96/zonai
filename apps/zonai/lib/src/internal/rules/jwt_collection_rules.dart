import 'package:zonai/src/internal/jwt_collection.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

JwtCollectionRules main() => JwtCollectionRules();

final class JwtCollectionRules
    extends InternalCollectionRules<JwtCollection, JwtEntry> {
  JwtCollectionRules() : super(jwts);

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
