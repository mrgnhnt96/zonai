import 'package:zonai_schema/src/internal/tables/abusers_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

AbuserRowRules main() => AbuserRowRules();

final class AbuserRowRules extends InternalRowRules<AbusersTable, AbuserEntry> {
  AbuserRowRules() : super(abusers);

  @override
  Future<bool> canCreate(Jwt? jwt, AbuserEntry row) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };

  @override
  Future<bool> canUpdate(
    Jwt? jwt,
    AbuserEntry before,
    AbuserEntry after,
  ) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };

  @override
  Future<bool> canDelete(Jwt? jwt, AbuserEntry row) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
