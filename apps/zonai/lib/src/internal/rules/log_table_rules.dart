import 'package:zonai/src/internal/tables/logs_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

LogTableRules main() => LogTableRules();

final class LogTableRules
    extends InternalTableRules<LogsTable, LogEntry> {
  LogTableRules() : super(logs);

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
