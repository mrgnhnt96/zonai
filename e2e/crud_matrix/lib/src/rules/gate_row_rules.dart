import 'package:zonai_crud_matrix/src/schemas/gates.dart';
import 'package:zonai_schema/zonai_schema.dart';

GateRowRules main() => GateRowRules();

/// The only assertion in this repo that can reach the worker-side serializer.
///
/// `551081f` fixed `serializeWhereValues` on the host: the CLI compiles its own
/// copy of zonai_schema, so releasing the CLI fixed every `Where` the *host*
/// builds. `02cfcef` is the other half -- a rule or operation calling `get.*`
/// with an `In`/`NotIn` builds `GetRecordRequest` *inside the worker*, and
/// `SendPortMessageIo` hands that map across the isolate boundary, so it
/// serializes with whatever copy of zonai_schema the project resolved. No CLI
/// release can reach it; that half needed a published one.
///
/// So the clause below is an `In`, on purpose, and it is here rather than on
/// `widgets` because a rule that reads the table it gates re-enters rule
/// evaluation.
///
/// The row is visible only when the read came back with exactly the two seeded
/// codes. `'007'` and `'7'` are separate rows, so this is also a leading-zero
/// discrimination check (#21) evaluated on the worker side rather than the
/// host's: a numeric coercion inside the worker returns one row twice or the
/// wrong row, and the count check below fails either way.
///
/// tool/ci/e2e/bin/drive.dart asserts BOTH directions -- visible while those
/// codes exist, hidden once they are deleted. Without the second one, a rule
/// that had silently degraded to `true` would look identical.
class GateRowRules extends RowRules<GateTable, Gate> {
  GateRowRules() : super(gates);

  static const _seededCodes = ['007', '7'];

  @override
  Future<bool> canView(Jwt? jwt, Gate row) async {
    final rows = await get.many(
      tableName: 'widgets',
      where: In('code', _seededCodes),
    );

    if (rows == null || rows.length != _seededCodes.length) {
      return false;
    }

    final codes = {for (final row in rows) row['code']};
    return codes.length == _seededCodes.length &&
        codes.containsAll(_seededCodes);
  }

  @override
  Future<bool> canUpdate(Jwt? jwt, Gate before, Gate after) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Gate row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Gate row) async => true;
}
