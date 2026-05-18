import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:raindrop/raindrop.dart' as rd;
import 'package:raindrop/raindrop.dart' hide Update;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/table_extensions.dart';
import 'package:zonai_schema/src/types/where_sql.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../false_delegate.dart';
import '../handlers/operations/operation_request.dart';

part 'collection_translator.dart';

/// Type-erased view of [CollectionOperations] for APIs (e.g. [DbOperations])
/// that hold multiple schemas. [Iterable] parameters use this type so call
/// sites may pass `[ConcreteOperations(), ...]` without explicit casts.
abstract interface class _DbCollection {
  const _DbCollection();

  (String, List<Object?>) _translate(
    BaseSqlDialect dialect,
    PerformOperationRequest request,
  );
}

/// Thin helpers around [rd.Raindrop] builders for a single [schema].
///
/// Each method returns a Raindrop builder. Builders are awaitable (they
/// implement [Future] via `ToQuery`), or you can chain more clauses and then
/// await. For row counts on update/delete, use [rd.Raindrop.execute] with
/// [rd.QueryBuilder.toQuery]; for `RETURNING`, use the SQLite extensions from
/// `package:raindrop_sqlite/raindrop_sqlite.dart` before awaiting.
abstract base class CollectionOperations<S extends rd.Schema<R>, R>
    implements _DbCollection {
  CollectionOperations(this.schema);

  final S schema;

  rd.Table<S, R> get table => rd.Table.getFor(schema);

  static rd.Raindrop? __db;
  static rd.Raindrop get _db => __db ??= rd.Raindrop(FalseDelegate());

  @nonVirtual
  late rd.Raindrop db = _db;

  rd.InsertWithValuesBuilder<rd.Schema<R>, R, R> insert(
    Map<String, dynamic> data,
  ) {
    return db.insert(into: schema).values([table.safeCreate(data)]).returning();
  }

  rd.InsertWithValuesBuilder<rd.Schema<R>, R, R> insertMany(List<R> entities) {
    return db.insert(into: schema).values(entities).returning();
  }

  rd.UpdateWhereBuilder<rd.Schema<R>, R, List<Object?>, void> update(
    List<Update> updates, {
    required Where where,
  }) {
    final updateables = <Updateable<dynamic>>[];

    final inferredColumns = <String>{};
    for (final column in table.columns) {
      switch (column.transformer) {
        case CreatedAtTransformer():
          inferredColumns.add(column.name);
        case UpdatedAtTransformer():
          inferredColumns.add(column.name);
          updateables.add(UpdateableColumn(column, DateTime.now()));
        case _:
      }
    }

    for (final update in updates) {
      switch (update) {
        case ColumnUpdate(:final column, :final value):
          if (!inferredColumns.contains(column)) {
            switch (value) {
              case LiteralUpdateValue(:final value):
                updateables.add(UpdateableColumn(table[column], value));
            }
          }
        case final ObjectUpdate update:
          updateables.addAll([
            for (final MapEntry(:key, :value) in update.object.entries)
              if (!inferredColumns.contains(key))
                UpdateableColumn(table[key], value),
          ]);
      }
    }

    return db
        .update(schema)
        .setAll(updateables)
        .where(RawSqlFilter(where.sql(table.name)));
  }

  rd.SelectFromBuilder<rd.Schema<R>, R, int> count({Where? where}) {
    final pkColumn = table.columns.firstWhere((c) => c.isPrimaryKey);
    final counting = pkColumn.transform<int>(SQL.function('COUNT', [pkColumn]));

    var builder = db.select(counting).from(schema);

    if (where != null) {
      builder = builder.where(RawSqlFilter(where.sql(table.name)));
    }

    return builder;
  }

  /// [selectFrom] with optional filter and pagination applied first.
  rd.SelectFromBuilder<rd.Schema<R>, R, R> list({
    Where? where,
    int? limit,
    int? offset,
    Selectable<dynamic>? groupBy,
  }) {
    var builder = db.select().from(schema);

    if (where != null) {
      builder = builder.where(RawSqlFilter(where.sql(table.name)));
    }

    if (limit != null) {
      builder = builder.limit(limit);
    }

    if (offset != null) {
      builder = builder.offset(offset);
    }

    if (groupBy != null) {
      builder = builder.groupBy(groupBy);
    }

    return builder;
  }

  rd.DeleteWhereBuilder<rd.Schema<R>, R, void> delete(
    Where where, {
    int? limit,
  }) {
    final builder = db
        .delete(from: schema)
        .where(RawSqlFilter(where.sql(table.name)));

    if (limit != null) {
      builder.limit(limit);
    }

    return builder;
  }

  rd.ToQuery<rd.Schema<R>, R> custom(
    String operation, {
    Where? where,
    Map<String, dynamic>? values,
  }) {
    throw UnimplementedError(
      'Custom operation has not been implemented: $operation',
    );
  }

  @override
  (String, List<Object?>) _translate(
    BaseSqlDialect dialect,
    PerformOperationRequest request,
  ) {
    final query = _query(request);
    return dialect.translate(query);
  }

  /// Builds the [Query] for [request] so callers (e.g. [DbOperations]) can run
  /// [BaseSqlDialect.translate] with the concrete schema row types for [S]/[R].
  rd.Query<dynamic, dynamic> _query(PerformOperationRequest request) {
    return switch (request) {
      CountOperationRequest(:final where) => count(where: where).toQuery(),
      CreateOperationRequest(:final object) => insert(object).toQuery(),
      UpdateOperationRequest(:final where, :final updates) => update(
        updates,
        where: where,
      ).toQuery(),
      DeleteOperationRequest(:final where, :final limit) => delete(
        where,
        limit: limit,
      ).toQuery(),
      ViewOperationRequest(:final where) => list(
        limit: 1,
        where: where,
      ).toQuery(),
      ListOperationRequest(:final where, :final limit, :final offset) => list(
        where: where,
        limit: limit,
        offset: offset,
      ).toQuery(),
      CustomOperationRequest(:final where, :final operation, :final values) =>
        custom(operation, where: where, values: values).toQuery(),
      PerformOperationRequest(:final operation) => throw StateError(
        'Invalid operation: $operation',
      ),
    };
  }
}

base mixin AuthOperations<S extends AuthCollection<R>, R>
    on CollectionOperations<S, R> {
  Future<Claims> addClaims({required Jwt jwt}) async {
    return Claims(jwt.claims);
  }
}

class Claims {
  const Claims(this.claims);

  factory Claims.fromJson(Map<String, dynamic> json) {
    return Claims(json['claims'] as Map<String, dynamic>);
  }

  final Map<String, dynamic> claims;

  Map<String, dynamic> toJson() {
    return {'claims': jsonDecode(jsonEncode(claims))};
  }
}
