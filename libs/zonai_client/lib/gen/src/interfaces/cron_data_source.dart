part of '../../interfaces.dart';

abstract interface class CronDataSource {
  const CronDataSource();

  Future<CronJobList> list({String? authorization});
  Future<void> run({required String name, String? authorization});
}
