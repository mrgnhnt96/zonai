import 'package:zonai/src/internal/logs_collection.dart';
import 'package:zonai_schema/src/operations/collection_operations.dart';

final class LogOperations
    extends CollectionOperations<LogsCollection, LogEntry> {
  LogOperations() : super(logs);
}

LogOperations main() => LogOperations();
