import 'package:zonai_schema/src/internal/logs_collection.dart';
import 'package:zonai_schema/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

LogCollectionRules main() => LogCollectionRules();

final class LogCollectionRules
    extends InternalCollectionRules<LogsCollection, LogEntry> {
  LogCollectionRules() : super(logs);

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
