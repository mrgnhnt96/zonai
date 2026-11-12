import 'package:zonai_schema/src/payloads/create_body.dart';
import 'package:zonai_schema/src/payloads/create_many_body.dart';
import 'package:zonai_schema/src/payloads/delete_body.dart';
import 'package:zonai_schema/src/payloads/parse_body.dart';
import 'package:zonai_schema/src/payloads/update_body.dart';

/// The body of `POST /db/batch`: writes across any tables that either all
/// land or none do.
///
/// Every step is checked first -- table and row rules, `before*` hooks, an
/// update's `expect` -- against the database as it stood before the batch.
/// Then every step's SQL runs in one SQLite transaction, so a failure in any
/// step rolls back the steps before it. `after*Success` hooks run once the
/// whole batch has committed.
///
/// Because every step is checked against the same starting state, a later
/// step does not see what an earlier step in the same batch wrote: an
/// `updateMany` does not match a row an earlier `create` added.
class BatchBody {
  const BatchBody({required this.operations});

  /// The most steps one batch may carry. A larger batch is refused with `400`
  /// before anything runs.
  static const maxOperations = 100;

  /// The steps, run in this order.
  final List<BatchOperation> operations;

  factory BatchBody.fromJson(Map<String, dynamic> json) =>
      parseBody('BatchBody', () => BatchBody._fromJson(json));

  factory BatchBody._fromJson(Map<String, dynamic> json) {
    final operations = json['operations'] as List<dynamic>;
    // Refused here, before the rate limiter counts a single step of it.
    if (operations.length > maxOperations) {
      throw InvalidBodyException(
        'BatchBody: ${operations.length} operations is more than the '
        '$maxOperations one batch may carry; split it',
      );
    }
    return BatchBody(
      operations: [
        for (final operation in operations)
          BatchOperation.fromJson(operation as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'operations': [for (final operation in operations) operation.toJson()],
    };
  }
}

/// One step of a [BatchBody]. Each has the same fields as its single-write
/// route, plus an `op` naming which one it is.
sealed class BatchOperation {
  const BatchOperation();

  /// Same as `POST /db`.
  const factory BatchOperation.create(CreateBody body) = BatchCreate;

  /// Same as `POST /db/many`.
  const factory BatchOperation.createMany(CreateManyBody body) =
      BatchCreateMany;

  /// Same as `PATCH /db`: exactly one row, and the batch fails with `404` when
  /// nothing matches.
  const factory BatchOperation.update(UpdateOneBody body) = BatchUpdate;

  /// Same as `PATCH /db/many`. Matching nothing is not an error.
  const factory BatchOperation.updateMany(UpdateBody body) = BatchUpdateMany;

  /// Same as `DELETE /db`: exactly one row, and the batch fails with `404`
  /// when nothing matches.
  const factory BatchOperation.delete(DeleteOneBody body) = BatchDelete;

  /// Same as `DELETE /db/many`. Matching nothing is not an error.
  const factory BatchOperation.deleteMany(DeleteBody body) = BatchDeleteMany;

  factory BatchOperation.fromJson(Map<String, dynamic> json) {
    return switch (json['op']) {
      'create' => BatchCreate(CreateBody.fromJson(json)),
      'createMany' => BatchCreateMany(CreateManyBody.fromJson(json)),
      'update' => BatchUpdate(UpdateOneBody.fromJson(json)),
      'updateMany' => BatchUpdateMany(UpdateBody.fromJson(json)),
      'delete' => BatchDelete(DeleteOneBody.fromJson(json)),
      'deleteMany' => BatchDeleteMany(DeleteBody.fromJson(json)),
      final op => throw InvalidBodyException(
        'BatchOperation: unknown op "$op"; expected one of create, '
        'createMany, update, updateMany, delete, deleteMany',
      ),
    };
  }

  /// The step's name on the wire, and in its [BatchResult].
  String get op;

  /// The table the step writes.
  String get table;

  Map<String, dynamic> toJson();
}

final class BatchCreate extends BatchOperation {
  const BatchCreate(this.body);

  final CreateBody body;

  @override
  String get op => 'create';

  @override
  String get table => body.table;

  @override
  Map<String, dynamic> toJson() => {'op': op, ...body.toJson()};
}

final class BatchCreateMany extends BatchOperation {
  const BatchCreateMany(this.body);

  final CreateManyBody body;

  @override
  String get op => 'createMany';

  @override
  String get table => body.table;

  @override
  Map<String, dynamic> toJson() => {'op': op, ...body.toJson()};
}

final class BatchUpdate extends BatchOperation {
  const BatchUpdate(this.body);

  final UpdateOneBody body;

  @override
  String get op => 'update';

  @override
  String get table => body.table;

  @override
  Map<String, dynamic> toJson() => {'op': op, ...body.toJson()};
}

final class BatchUpdateMany extends BatchOperation {
  const BatchUpdateMany(this.body);

  final UpdateBody body;

  @override
  String get op => 'updateMany';

  @override
  String get table => body.table;

  @override
  Map<String, dynamic> toJson() => {'op': op, ...body.toJson()};
}

final class BatchDelete extends BatchOperation {
  const BatchDelete(this.body);

  final DeleteOneBody body;

  @override
  String get op => 'delete';

  @override
  String get table => body.table;

  @override
  Map<String, dynamic> toJson() => {'op': op, ...body.toJson()};
}

final class BatchDeleteMany extends BatchOperation {
  const BatchDeleteMany(this.body);

  final DeleteBody body;

  @override
  String get op => 'deleteMany';

  @override
  String get table => body.table;

  @override
  Map<String, dynamic> toJson() => {'op': op, ...body.toJson()};
}

/// What one step of a committed batch did, in the order the steps were sent.
class BatchResult {
  const BatchResult({
    required this.op,
    required this.table,
    required this.count,
    this.rows = const [],
  });

  /// The step's [BatchOperation.op].
  final String op;

  final String table;

  /// Rows the step created, updated or deleted.
  final int count;

  /// The rows as they are now, for a create or update; the same rows a single
  /// write's route returns. Always empty for a delete, which returns no rows
  /// on its own route either.
  final List<Map<String, Object?>> rows;

  factory BatchResult.fromJson(Map<String, dynamic> json) =>
      parseBody('BatchResult', () => BatchResult._fromJson(json));

  factory BatchResult._fromJson(Map<String, dynamic> json) {
    return BatchResult(
      op: json['op'] as String,
      table: json['table'] as String,
      count: json['count'] as int,
      rows: [
        for (final row in json['rows'] as List<dynamic>)
          (row as Map).cast<String, Object?>(),
      ],
    );
  }

  Map<String, Object?> toJson() {
    return {'op': op, 'table': table, 'count': count, 'rows': rows};
  }
}
