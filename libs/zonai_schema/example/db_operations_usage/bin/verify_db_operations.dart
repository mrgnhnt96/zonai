import 'package:db_operations_usage/demo_operations.dart';
import 'package:zonai_schema/src/handlers/operations/db_operations.dart';

/// Exercises [DbOperations]: reads JSON [UnknownRequest] lines from stdin (same
/// framing as [MessageHandler]), translates `operation.perform` payloads into
/// SQLite SQL via [PerformOperationResponse], and writes JSON lines to stdout.
///
/// Try a list (no filter):
/// `{"path":"operation.perform","id":"1","collection":"demo_widgets","operation":"list","limit":5,"offset":0}`
///
/// Create a row:
/// `{"path":"operation.perform","id":"2","collection":"demo_widgets","operation":"create","object":{"title":"hello"}}`
///
/// Type kill, quit, exit, or q on a line to stop (see [MessageHandler]).
void main() {
  print('DbOperations demo — JSON lines on stdin, translated SQL on stdout.');
  print(
    r'List example: {"path":"operation.perform","id":"1","collection":"demo_widgets","operation":"list","limit":5,"offset":0}',
  );
  print(
    r'Create example: {"path":"operation.perform","id":"2","collection":"demo_widgets","operation":"create","object":{"title":"hello"}}',
  );
  print('Type kill, quit, exit, or q on a line to stop.');

  final db = DbOperations(operations: [DemoOperations()]);

  db.start();
}
