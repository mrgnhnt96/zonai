import 'package:zonai_schema/src/internal/tables/abusers_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/internal/abusers_table.dart' show AbuserEntry;
import 'package:zonai_schema/src/types/jwt.dart';

AbuserTableRules main() => AbuserTableRules();

final class AbuserTableRules
    extends InternalTableRules<AbusersTable, AbuserEntry> {
  AbuserTableRules() : super(abusers);

  @override
  Future<bool> canCreate(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };

  @override
  Future<bool> canUpdate(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
