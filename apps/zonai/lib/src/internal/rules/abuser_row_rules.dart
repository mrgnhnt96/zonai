import 'package:zonai/src/internal/tables/abusers_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/internal/abusers_table.dart'
    show AbuserEntry;
import 'package:zonai_schema/src/types/jwt.dart';

AbuserRowRules main() => AbuserRowRules();

final class AbuserRowRules
    extends InternalRowRules<AbusersTable, AbuserEntry> {
  AbuserRowRules() : super(abusers);

  @override
  Future<bool> canDelete(Jwt? jwt, AbuserEntry row) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
