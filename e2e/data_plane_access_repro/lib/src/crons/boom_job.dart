import 'package:zonai_schema/zonai_schema.dart';

BoomJob main() => BoomJob();

/// Run only on demand: writes one note, then throws, so a failed
/// `POST /crons/run` can be checked to still report (and keep) that write.
final class BoomJob extends CronJob {
  BoomJob() : super(name: 'boom', schedule: Schedule.parse('0 0 1 1 *'));

  @override
  Future<void> run() async {
    mutate.create.one(
      tableName: 'notes',
      object: {'title': 'boom-made', 'owner_id': ApiTokenJwt.sentinel},
    );
    throw StateError('boom');
  }
}
