import 'package:zonai_client/server.dart';
import 'package:zonai_schema/payloads.dart';

/// Storage usage for the maintenance screen.
///
/// Its own call rather than a field on the dashboard's metrics: collecting it
/// shells out to `df`, walks the photos directory and makes two pragma round
/// trips per database file, and the dashboard polls on a timer.
Future<StorageMetrics> fetchStorageMetrics({required Server server}) {
  return server.dashboard.storage();
}
