import 'package:clock/clock.dart';
import 'package:revali_router/revali_router.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/zonai_schema.dart';
import 'package:raindrop/raindrop.dart';

final class BlackList implements LifecycleComponent {
  const BlackList();

  Future<GuardResult> check(@Ip() String ipAddress) async {
    final db = await zonaiDB.open();

    final rows = await db
        .select()
        .from(abusers)
        .where(abusers.ip.equals(ipAddress));

    final now = clock.now();
    for (final row in rows) {
      if (row.blackListed) {
        return const .block(statusCode: 403, body: 'Unauthorized');
      }

      if (row.blockedUntil case final until? when until.isAfter(now)) {
        return .block(statusCode: 403, body: 'Unauthorized');
      }
    }

    return const .pass();
  }
}
