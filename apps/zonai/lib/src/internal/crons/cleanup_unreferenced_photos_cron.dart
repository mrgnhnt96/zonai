import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';
import 'package:zonai_schema/src/handlers/messages/message_handler.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class CleanupUnreferencedPhotosCron extends CronJob {
  CleanupUnreferencedPhotosCron()
    : super(
        name: '_cleanup_unreferenced_photos',
        schedule: Schedule.parse('0 5 * * *'),
        strict: false,
      );

  @override
  Future<void> run() async {
    final response = await msg.request<CleanupUnreferencedPhotosResponse>(
      CleanupUnreferencedPhotosRequest(),
    );

    logger.info('Deleted ${response.deletedCount} unreferenced photo(s)');
  }
}

CleanupUnreferencedPhotosCron main() => CleanupUnreferencedPhotosCron();
