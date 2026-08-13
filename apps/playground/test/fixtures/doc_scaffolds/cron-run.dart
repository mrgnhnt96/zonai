// Statements inside a cron job's `run()` -- the body the docs show on its own
// when they are talking about what a job may do rather than how to declare it.
import 'package:zonai_schema/zonai_schema.dart';

final class ExampleJob extends CronJob {
  ExampleJob() : super(name: 'example', schedule: Schedule.parse('0 3 * * *'));

  @override
  Future<void> run() async {
    // <<body>>
  }
}
