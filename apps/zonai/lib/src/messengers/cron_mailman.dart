import 'package:raindrop/raindrop.dart';
import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/internal/tables/crons_table.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';

class CronMailman extends Mailman<CronRequest, CronResponse> with Receivable {
  CronMailman()
    : super(
        debugName: debug,
        executablePath: settings.compiledCronsPath,
        fromJson: CronResponse.fromJson,
      );

  static const debug = 'CRON';

  @override
  bool isOutOfBandNotification(CronResponse response) {
    return response is JobStarted ||
        response is JobCompleted ||
        response is JobFailed;
  }

  void start() {
    send(StartCronsRequest()).then(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        logger.error('Failed to start cron worker', error, stackTrace);
      },
    );
  }

  void stop() {
    send(StopCronsRequest());
  }

  @override
  Future<CronResponse> onRequest(CronRequest request) async {
    switch (request) {
      case RunCronJobRequest():
        throw Exception(
          '$RunCronJobRequest should not be called to main thread',
        );
      case StartCronsRequest():
        throw Exception(
          '$StartCronsRequest should not be called to main thread',
        );
      case StopCronsRequest():
        throw Exception(
          '$StopCronsRequest should not be called to main thread',
        );

      case CleanupUnreferencedPhotosRequest(:final id):
        final deletedCount = await zonaiDB.cleanupUnreferencedPhotos();
        return CleanupUnreferencedPhotosResponse(
          id: id,
          deletedCount: deletedCount,
        );

      case final LastJobRunRequest request:
        final db = await zonaiDB.open();

        final rows = await db
            .select()
            .from(crons)
            .where(crons.name.equals(request.name))
            .orderBy({crons.started: Order.desc})
            .limit(1);

        if (rows.isEmpty) {
          return LastJobRunResponse(
            id: request.id,
            name: request.name,
            time: null,
            wasSuccessful: false,
          );
        }

        final lastRun = rows.first;

        return LastJobRunResponse(
          id: request.id,
          name: request.name,
          time: lastRun.started,
          wasSuccessful: lastRun.completed != null,
        );
    }
  }

  @override
  Future<void> onUnexpectedDelivery(CronResponse response) async {
    switch (response) {
      case CronJobRunResponse():
        break;
      case JobStarted(:final name):
        logger.info('[CRON] started: ${response.name}');

        final db = await zonaiDB.open();

        await db.insert(into: crons).values([CronEntry.create(name: name)]);
      case JobCompleted(:final name):
        logger.info('[CRON] completed: ${response.name}');

        final db = await zonaiDB.open();

        await db
            .update(crons)
            .set(crons.completed.to(DateTime.now()))
            .where(
              crons.name.equals(name) &
                  crons.completed.isNull() &
                  crons.failed.isNull(),
            );
      case JobFailed(:final name, :final error, :final stackTrace):
        logger.warn('[CRON] failed: ${response.name}');

        final db = await zonaiDB.open();

        await db
            .update(crons)
            .set(
              crons.failed.to(DateTime.now()),
              crons.error.to(error),
              crons.stackTrace.to(stackTrace),
            )
            .where(
              crons.name.equals(name) &
                  crons.completed.isNull() &
                  crons.failed.isNull(),
            );

      case CronsStopped():
      case CronsStarted():
      case LastJobRunResponse():
      case CleanupUnreferencedPhotosResponse():
        logger.warn(
          'Ignoring unexpected cron notification: ${response.runtimeType}',
        );
    }
  }
}
