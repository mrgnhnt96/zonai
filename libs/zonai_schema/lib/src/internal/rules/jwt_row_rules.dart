import 'package:zonai_schema/src/internal/tables/jwt_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

JwtRowRules main() => JwtRowRules();

final class JwtRowRules extends InternalRowRules<JwtTable, JwtEntry> {
  JwtRowRules() : super(jwts);

  @override
  Future<bool> canDelete(Jwt? jwt, JwtEntry row) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
