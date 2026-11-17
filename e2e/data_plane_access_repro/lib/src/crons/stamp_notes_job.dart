import 'package:zonai_schema/zonai_schema.dart';

StampNotesJob main() => StampNotesJob();

/// Run only on demand, by `api_token_http_e2e_test.dart`: writes a known set
/// of rows so `POST /crons/run` can be checked to count them -- two notes
/// created, and the one note the test planted renamed.
///
/// The new notes belong to the unbound-token owner, so a token can read them
/// back the moment the run answers.
final class StampNotesJob extends CronJob {
  StampNotesJob()
    : super(name: 'stamp_notes', schedule: Schedule.parse('0 0 1 1 *'));

  @override
  Future<void> run() async {
    for (final n in [1, 2]) {
      mutate.create.one(
        tableName: 'notes',
        object: {'title': 'cron-made-$n', 'owner_id': ApiTokenJwt.sentinel},
      );
    }
    mutate.update.one(
      table: 'notes',
      updates: [Update.column('title', .literal('cron-stamped'))],
      where: Eq('owner_id', 'cron-target'),
    );
  }
}
