import 'package:clock/clock.dart';
import 'package:revali_router/revali_router.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/db_mutator/zonai_db/zonai_db.dart';
import 'package:zonai_schema/zonai_schema.dart';
import 'package:raindrop/raindrop.dart';

final class BlackList implements LifecycleComponent {
  const BlackList();

  /// When the abusers table has been observed empty, skip the per-request
  /// SELECT until this instant. Avoids a SQLite round-trip on every request
  /// for the common "nobody is banned" case.
  static DateTime? _emptyUntil;
  static const _emptyTtl = Duration(seconds: 30);

  Future<GuardResult> check(@Ip() String ipAddress) async {
    final now = clock.now();
    if (_emptyUntil case final until? when until.isAfter(now)) {
      return const .pass();
    }

    final db = await zonaiDB.open();

    final rows = await db
        .select()
        .from(abusers)
        .where(abusers.ip.equals(ipAddress));

    if (rows.isEmpty) {
      // Recheck occasionally in case an abuser is added at runtime.
      _emptyUntil = now.add(_emptyTtl);
      return const .pass();
    }
    _emptyUntil = null;

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
