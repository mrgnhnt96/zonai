import 'package:zonai/src/internal/logs_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

LogRecordRules main() => LogRecordRules();

final class LogRecordRules
    extends InternalRecordRules<LogsTable, LogEntry> {
  LogRecordRules() : super(logs);

  @override
  Future<bool> canDelete(Jwt? jwt, LogEntry record) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
