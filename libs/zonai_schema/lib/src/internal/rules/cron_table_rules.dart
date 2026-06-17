import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/internal/tables/crons_table.dart';
import 'package:zonai_schema/src/types/jwt.dart';

CronTableRules main() => CronTableRules();

final class CronTableRules extends InternalTableRules<CronsTable, CronEntry> {
  CronTableRules() : super(crons);

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
