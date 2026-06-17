import 'package:zonai_schema/src/internal/tables/crons_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

CronRowRules main() => CronRowRules();

final class CronRowRules extends InternalRowRules<CronsTable, CronEntry> {
  CronRowRules() : super(crons);

  @override
  Future<bool> canDelete(Jwt? jwt, CronEntry row) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
