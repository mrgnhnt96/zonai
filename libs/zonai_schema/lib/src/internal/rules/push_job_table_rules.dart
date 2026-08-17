import 'package:zonai_schema/src/internal/tables/push_jobs_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

PushJobTableRules main() => PushJobTableRules();

final class PushJobTableRules
    extends InternalTableRules<PushJobsTable, PushJobEntry> {
  PushJobTableRules() : super(pushJobs);

  @override
  Future<bool> canDelete(Jwt? jwt) async => switch (jwt?.admin.canEdit) {
    true => true,
    _ => false,
  };
}
