import 'package:zonai/src/internal/tables/jwt_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

JwtTableRules main() => JwtTableRules();

final class JwtTableRules extends InternalTableRules<JwtTable, JwtEntry> {
  JwtTableRules() : super(jwts);

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
