// Statements inside a cron job's `run()` -- the body the docs show on its own
// when they are talking about what a job may do rather than how to declare it.
//
// The members are the stand-ins the surrounding prose assumes ("the rows that
// came back", "the user being notified"). Getters rather than locals, for the
// reason given in side-effects.dart.
import 'package:zonai_schema/zonai_schema.dart';

final class ExampleJob extends CronJob {
  ExampleJob() : super(name: 'example', schedule: Schedule.parse('0 3 * * *'));

  /// Rows here come back from `get.many` as maps, not typed rows -- these
  /// fragments read `user['email']`, which is what the API really returns.
  Map<String, Object?> get user => throw UnimplementedError();
  Map<String, Object?> get admin => throw UnimplementedError();
  List<Map<String, Object?>> get rows => throw UnimplementedError();
  List<Map<String, Object?>> get stale => throw UnimplementedError();
  DateTime get cutoff => throw UnimplementedError();
  Object get error => throw UnimplementedError();
  String get userId => throw UnimplementedError();
  int get daysLeft => throw UnimplementedError();

  @override
  Future<void> run() async {
    // <<body>>
  }
}
