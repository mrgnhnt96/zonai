part of '../../interfaces.dart';

abstract interface class CronDataSource {
  const CronDataSource();

  Future<CronJobList> list({String? authorization});
  Future<CronRunResult> run({required String name, String? authorization});
}
