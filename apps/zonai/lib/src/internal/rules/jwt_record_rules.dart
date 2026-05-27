import 'package:zonai/src/internal/jwt_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

JwtRecordRules main() => JwtRecordRules();

final class JwtRecordRules
    extends InternalRecordRules<JwtTable, JwtEntry> {
  JwtRecordRules() : super(jwts);

  @override
  Future<bool> canDelete(Jwt? jwt, JwtEntry record) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
