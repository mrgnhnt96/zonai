import 'package:zonai_schema/src/internal/tables/push_jobs_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

PushJobRowRules main() => PushJobRowRules();

final class PushJobRowRules
    extends InternalRowRules<PushJobsTable, PushJobEntry> {
  PushJobRowRules() : super(pushJobs);

  @override
  Future<bool> canDelete(Jwt? jwt, PushJobEntry row) async =>
      switch (jwt?.admin.canEdit) {
        true => true,
        _ => false,
      };
}
