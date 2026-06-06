import 'package:zonai/src/internal/tables/logs_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

LogRowRules main() => LogRowRules();

final class LogRowRules extends InternalRowRules<LogsTable, LogEntry> {
  LogRowRules() : super(logs);

  @override
  Future<bool> canDelete(Jwt? jwt, LogEntry row) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
