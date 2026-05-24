import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:raindrop/raindrop.dart' as rd;
import 'package:raindrop/raindrop.dart' hide Update, OrderByTerm;
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

    updateLoop:
    for (final update in updates) {
      switch (update) {
        case ColumnUpdate(:final column, :final value):
          final pathParts = column.split('.');
          if (pathParts.length == 1) {
            if (_convertUpdateValue(column, value, inferredColumns)
                case final converted?) {
              updateables.add(converted);
            }
          } else {
            if (pathParts.any((p) => p.isEmpty)) {
              throw ArgumentError.value(
                column,
                'column',
                'Dotted column path must not contain empty segments',
              );
            }
            final base = pathParts.first;
            if (inferredColumns.contains(base)) {
              continue updateLoop;
            }
            final col = table[base];
            if (col.transformer is! MapTransformer) {
              throw ArgumentError(
                'Dotted column "$column" is only supported on JSON map columns '
                '("${col.name}"): use SchemaBuilder.map / mapAs. '
                'Got ${col.transformer.runtimeType}.',
              );
            }
            if (_convertNestedJsonPathUpdate(
                  col,
                  pathParts.sublist(1),
                  value,
                  column,
                )
                case final converted?) {
              updateables.add(converted);
            }
          }
        case final ObjectUpdate update:
          for (final MapEntry(:key, :value) in update.object.entries) {
            if (inferredColumns.contains(key)) {
              continue;
            }

            if (_tryUpdateValue(value) case final nested?) {
              if (_convertUpdateValue(key, nested, inferredColumns)
                  case final converted?) {
                updateables.add(converted);
              }
            } else {
              final col = table[key];
              if (col.transformer is MapTransformer && value is Map) {
                updateables.add(
                  UpdateableColumn(
                    col,
                    _jsonObjectPatchExpression(
                      col,
                      Map<String, dynamic>.from(value),
                    ),
                  ),
                );
              } else {
                updateables.add(UpdateableColumn(col, value));
              }
            }
          }
      }
    }

    return db
        .update(schema)
        .setAll(updateables)
        .where(RawSqlFilter(where.sql(table.name)));
  }

  UpdateableColumn? _convertUpdateValue(
    String columnName,
    UpdateValue value,
    Set<String> inferredColumns,
  ) {
    if (inferredColumns.contains(columnName)) {
      return null;
    }
    final col = table[columnName];
    switch (value) {
      case Literal(:final value):
        return UpdateableColumn(col, value);
      case Increment():
        if (col.transformer is MapTransformer) {
          throw ArgumentError(
            'Increment is not supported on JSON map columns: '
            '$columnName',
          );
        }
        return UpdateableColumn(col, SQL([col, const RawSQL('+'), 1]));
      case Decrement():
        if (col.transformer is MapTransformer) {
          throw ArgumentError(
            'Decrement is not supported on JSON map columns: '
            '$columnName',
          );
        }
        return UpdateableColumn(col, SQL([col, const RawSQL('-'), 1]));
      case Add(:final value):
        if (col.transformer is ListTransformer) {
          return UpdateableColumn(col, _jsonListAppendExpression(col, value));
        }
        if (col.transformer is MapTransformer) {
          throw ArgumentError(
            'Add is not supported on JSON map columns: '
            '$columnName',
          );
        }
        return UpdateableColumn(col, SQL([col, const RawSQL('+'), value]));
      case Remove(:final value):
        if (col.transformer is ListTransformer) {
          return UpdateableColumn(
            col,
            _jsonListRemoveMatchingExpression(col, value),
          );
        }
        if (col.transformer is MapTransformer) {
          throw ArgumentError(
            'Remove is not supported on JSON map columns: '
            '$columnName',
          );
        }
        return UpdateableColumn(col, SQL([col, const RawSQL('-'), value]));
      case AddAll(:final values):
        if (col.transformer is! ListTransformer) {
          throw ArgumentError(
            'AddAll is only supported on list columns (ListTransformer): '
            '$columnName',
          );
        }
        return UpdateableColumn(col, _jsonListAppendAllExpression(col, values));
      case RemoveAll(:final values):
        if (col.transformer is! ListTransformer) {
          throw ArgumentError(
            'RemoveAll is only supported on list columns (ListTransformer): '
            '$columnName',
          );
        }
        return UpdateableColumn(
          col,
          _jsonListRemoveAllMatchingExpression(col, values),
        );
    }
  }

  /// SQLite JSON path (`$.a.b` or `$["a-b"]` for non-identifier keys).
  static String _sqliteJsonObjectPath(List<String> segments) {
    final buf = StringBuffer(r'$');
    for (final s in segments) {
      if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(s)) {
        buf.write('.$s');
      } else {
        buf.write('[${jsonEncode(s)}]');
      }
    }
    return buf.toString();
  }

  UpdateableColumn? _convertNestedJsonPathUpdate(
    Column<dynamic, dynamic> col,
    List<String> pathSegments,
    UpdateValue value,
    String columnSpec,
  ) {
    return switch (value) {
      Literal(:final value) => UpdateableColumn(
        col,
        _jsonObjectSetExpression(col, pathSegments, value),
      ),
      _ => throw ArgumentError(
        'Only literal UpdateValue is supported for nested JSON map paths '
        '("$columnSpec"): ${value.runtimeType}',
      ),
    };
  }

  /// `json_set(COALESCE(col,'{}'), path, value)` for a nested key.
  rd.SQL _jsonObjectSetExpression(
    rd.Column<dynamic, dynamic> col,
    List<String> pathSegments,
    Object? value,
  ) {
    final path = _sqliteJsonObjectPath(pathSegments).replaceAll("'", "''");
    return rd.SQL([
      const rd.RawSQL('json_set(COALESCE('),
      col,
      rd.RawSQL(", '{}'), '$path'"),
      const rd.RawSQL(', '),
      value,
      const rd.RawSQL(')'),
    ]);
  }

  /// RFC 7396 JSON merge patch into an object column (plain [ObjectUpdate]).
  rd.SQL _jsonObjectPatchExpression(
    rd.Column<dynamic, dynamic> col,
    Map<String, dynamic> patch,
  ) {
    final wire = jsonEncode(patch);
    return rd.SQL([
      const rd.RawSQL('json_patch(COALESCE('),
      col,
      const rd.RawSQL(", '{}'), "),
      wire,
      const rd.RawSQL(')'),
    ]);
  }

  /// `json_insert(COALESCE(col,'[]'), '$[' || json_array_length(...) || ']',
  /// ?)` — appends one JSON value to the stored array.
  rd.SQL _jsonListAppendExpression(
    rd.Column<dynamic, dynamic> col,
    Object? value,
  ) {
    return rd.SQL([
      const rd.RawSQL('json_insert(COALESCE('),
      col,
      const rd.RawSQL(r", '[]'), '$[' || json_array_length(COALESCE("),
      col,
      const rd.RawSQL(r", '[]')) || ']'"),
      const rd.RawSQL(', '),
      value,
      const rd.RawSQL(')'),
    ]);
  }

  /// Drops every array element equal to `value` (SQLite json_each comparison),
  /// preserving order among kept elements.
  rd.SQL _jsonListRemoveMatchingExpression(
    rd.Column<dynamic, dynamic> col,
    Object? value,
  ) {
    return rd.SQL([
      const rd.RawSQL(
        'COALESCE((SELECT json_group_array(e.value) FROM json_each(COALESCE(',
      ),
      col,
      const rd.RawSQL(", '[]')) AS e WHERE e.value != "),
      value,
      const rd.RawSQL("), '[]')"),
    ]);
  }

  /// Concatenates the stored JSON array with [values] (each appended in order).
  rd.SQL _jsonListAppendAllExpression(
    rd.Column<dynamic, dynamic> col,
    List<Object?> values,
  ) {
    final wire = jsonEncode(values);
    return rd.SQL([
      const rd.RawSQL(
        'COALESCE((SELECT json_group_array(elem) FROM (SELECT value AS elem FROM '
        'json_each(COALESCE(',
      ),
      col,
      const rd.RawSQL(
        r", '[]')) UNION ALL SELECT value AS elem FROM json_each(",
      ),
      wire,
      const rd.RawSQL('))), \'[]\')'),
    ]);
  }

  /// Removes every element whose [json_each] `value` appears in [values].
  rd.SQL _jsonListRemoveAllMatchingExpression(
    rd.Column<dynamic, dynamic> col,
    List<Object?> values,
  ) {
    final wire = jsonEncode(values);
    return rd.SQL([
      const rd.RawSQL(
        'COALESCE((SELECT json_group_array(e.value) FROM json_each(COALESCE(',
      ),
      col,
      const rd.RawSQL(
        r", '[]')) AS e WHERE e.value NOT IN (SELECT value FROM json_each(",
      ),
      wire,
      const rd.RawSQL('))), \'[]\')'),
    ]);
  }

  /// When [ObjectUpdate] embeds [UpdateValue] maps (e.g. from JSON), apply the
  /// same semantics as [ColumnUpdate]. Plain maps without a known `type`
  /// remain literal row values.
  UpdateValue? _tryUpdateValue(Object? raw) {
    if (raw is! Map) {
      return null;
    }

    try {
      return UpdateValue.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  rd.SelectFromBuilder<rd.Schema<R>, R, int> count({Where? where}) {
    final pkColumn = table.columns.firstWhere((c) => c.isPrimaryKey);
    final counting = _CountColumn(pkColumn);

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
    List<OrderByTerm>? orderBy,
    Selectable<dynamic>? groupBy,
  }) {
    var builder = db.select().from(schema);

    if (where != null) {
      builder = builder.where(RawSqlFilter(where.sql(table.name)));
    }

    if (orderBy != null) {
      for (final term in orderBy) {
        builder = builder.orderBy(
          table[term.column],
          ascending: term.direction == SortDirection.asc,
        );
      }
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
      return builder.limit(limit);
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
      ReadOperationRequest(:final where) => list(
        limit: 1,
        where: where,
      ).toQuery(),
      ListOperationRequest(
        :final where,
        :final limit,
        :final offset,
        :final orderBy,
      ) =>
        list(
          where: where,
          limit: limit,
          offset: offset,
          orderBy: orderBy,
        ).toQuery(),
      CustomOperationRequest(:final where, :final operation, :final values) =>
        custom(operation, where: where, values: values).toQuery(),
      PerformOperationRequest(:final operation) => throw StateError(
        'Invalid operation: $operation',
      ),
    };
  }
}

final class _CountColumn extends rd.Expression<int> {
  _CountColumn(this._column);

  final rd.Column<dynamic, dynamic> _column;

  @override
  rd.SQL build() => rd.SQL.function('COUNT', [_column]);
}

base mixin AuthOperations<S extends AuthCollection<R>, R>
    on CollectionOperations<S, R> {
  Future<Claims> addClaims({required Jwt jwt}) async {
    return Claims(jwt.claims);
  }

  Future<MagicLinkConfig> magicLinkConfig() async {
    return MagicLinkConfig();
  }

  Future<ResetPasswordConfig> resetPasswordConfig() async {
    return ResetPasswordConfig();
  }

  Future<VerifyEmailConfig> verifyEmailConfig() async {
    return VerifyEmailConfig();
  }
}

class MagicLinkConfig {
  MagicLinkConfig({
    this.path = '/auth/magic-link',
    this.expiresIn = const Duration(minutes: 10),
  });

  factory MagicLinkConfig.fromJson(Map<String, dynamic> json) {
    return MagicLinkConfig(
      path: json['path'] as String,
      expiresIn: Duration(seconds: json['expiresIn'] as int),
    );
  }

  /// The path to the magic link endpoint.
  ///
  /// Can include the base url if the domain differs from the app config's
  /// base url.
  final String path;

  /// The duration for which the magic link is valid.
  final Duration expiresIn;

  Map<String, dynamic> toJson() {
    return {'path': path, 'expiresIn': expiresIn.inSeconds};
  }
}

class VerifyEmailConfig {
  VerifyEmailConfig({
    this.path = '/auth/verify-email',
    this.expiresIn = const Duration(hours: 24),
  });

  factory VerifyEmailConfig.fromJson(Map<String, dynamic> json) {
    return VerifyEmailConfig(
      path: json['path'] as String,
      expiresIn: Duration(seconds: json['expiresIn'] as int),
    );
  }

  /// The path to the verify email endpoint.
  ///
  /// Can include the base url if the domain differs from the app config's
  /// base url.
  final String path;

  /// The duration for which the verify email link is valid.
  final Duration expiresIn;

  Map<String, dynamic> toJson() {
    return {'path': path, 'expiresIn': expiresIn.inSeconds};
  }
}

class ResetPasswordConfig {
  ResetPasswordConfig({
    this.path = '/auth/reset-password',
    this.expiresIn = const Duration(minutes: 10),
  });

  factory ResetPasswordConfig.fromJson(Map<String, dynamic> json) {
    return ResetPasswordConfig(
      path: json['path'] as String,
      expiresIn: Duration(seconds: json['expiresIn'] as int),
    );
  }

  /// The path to the reset password endpoint.
  ///
  /// Can include the base url if the domain differs from the app config's
  /// base url.
  final String path;

  /// The duration for which the reset password is valid.
  final Duration expiresIn;

  Map<String, dynamic> toJson() {
    return {'path': path, 'expiresIn': expiresIn.inSeconds};
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
