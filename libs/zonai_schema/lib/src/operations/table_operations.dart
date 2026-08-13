import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart'
    show SQLiteInsertReturning;
import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as rd;
import 'package:zonai_schema/src/table_extensions.dart';
import 'package:zonai_schema/src/types/where_sql.dart';
import 'package:zonai_schema/zonai_schema.dart';

import '../false_delegate.dart';
import '../handlers/operations/operation_request.dart';

part 'table_translator.dart';
part 'view_operations.dart';

/// Type-erased view of [TableOperations] for APIs (e.g. [DbOperations])
/// that hold multiple schemas. [Iterable] parameters use this type so call
/// sites may pass `[ConcreteOperations(), ...]` without explicit casts.
abstract interface class _DbTable {
  const _DbTable();

  (String, List<Object?>) _translate(
    SqlDialect dialect,
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
abstract base class TableOperations<S extends rd.Schema<R>, R>
    implements _DbTable {
  TableOperations(this.schema);

  final S schema;

  rd.TableMeta<S, R> get table => schema.$ as rd.TableMeta<S, R>;

  rd.Column<dynamic, dynamic> _requireColumn(String name) {
    for (final column in table.columns) {
      if (column.name == name) return column;
    }
    throw ColumnNotFoundException(table: table.name, columnName: name);
  }

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

  rd.UpdateWhereBuilder<rd.Schema<R>, R, void> update(
    List<Update> updates, {
    required Where where,
  }) {
    final updateables = <Updateable<dynamic>>[];

    final inferredColumns = <String>{};
    final watchedUpdateColumns =
        <(rd.Column<dynamic, dynamic>, UpdatedWhenTransformer)>[];
    for (final column in table.columns) {
      switch (column.transformer) {
        case CreatedAtTransformer():
          inferredColumns.add(column.name);
        case UpdatedAtTransformer():
          inferredColumns.add(column.name);
          updateables.add(UpdateableColumn(column, DateTime.now()));
        case final UpdatedWhenTransformer t:
          inferredColumns.add(column.name);
          watchedUpdateColumns.add((column, t));
        case _:
      }
    }

    if (watchedUpdateColumns.isNotEmpty) {
      final updatingColumns = <String>{};
      for (final update in updates) {
        switch (update) {
          case ColumnUpdate(:final column):
            updatingColumns.add(column.split('.').first);
          case ObjectUpdate(:final object):
            updatingColumns.addAll(object.keys);
        }
      }
      for (final (column, transformer) in watchedUpdateColumns) {
        if (updatingColumns.contains(transformer.watchedColumn)) {
          updateables.add(UpdateableColumn(column, DateTime.now()));
        }
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
            final col = _requireColumn(base);
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

            if (tryParseUpdateValue(value) case final nested?) {
              if (_convertUpdateValue(key, nested, inferredColumns)
                  case final converted?) {
                updateables.add(converted);
              }
            } else {
              final col = _requireColumn(key);
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
                updateables.add(
                  UpdateableColumn(col, _decodeUpdateWireValue(col, value)),
                );
              }
            }
          }
      }
    }

    return db
        .update(schema)
        .setAll(updateables)
        .where(_whereFilter(where, table.name));
  }

  /// Decodes API/wire values (e.g. [String] ids) before [Column.encode].
  Object? _decodeUpdateWireValue(
    rd.Column<dynamic, dynamic> col,
    Object? value,
  ) {
    if (value == null) return null;
    return col.decode(value);
  }

  UpdateableColumn? _convertUpdateValue(
    String columnName,
    UpdateValue value,
    Set<String> inferredColumns,
  ) {
    if (inferredColumns.contains(columnName)) {
      return null;
    }
    final col = _requireColumn(columnName);
    switch (value) {
      case Literal(:final value):
        return UpdateableColumn(col, _decodeUpdateWireValue(col, value));
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

  rd.SelectFromBuilder<rd.Schema<R>, R, int> count({Where? where}) {
    final pkColumn = table.columns.firstWhere((c) => c.isPrimaryKey);
    final counting = _CountColumn(pkColumn);

    rd.SelectFromBuilder<rd.Schema<R>, R, int> builder = db
        .select(counting)
        .from(schema);

    if (where != null) {
      builder = builder.where(_whereFilter(where, table.name));
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
      builder = builder.where(_whereFilter(where, table.name));
    }

    final resolvedOrderBy = orderBy ?? _defaultOrderByFor(table);
    if (resolvedOrderBy != null && resolvedOrderBy.isNotEmpty) {
      builder = builder.orderBy({
        for (final term in resolvedOrderBy)
          table[term.column]: term.direction == SortDirection.asc
              ? Order.asc
              : Order.desc,
      });
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
    if (limit == null) {
      return db
          .delete(from: schema)
          .where(_whereFilter(where, table.name));
    }

    // sqlite3mc amalgamation cannot parse `DELETE … LIMIT` unless lemon was
    // regenerated with SQLITE_ENABLE_UPDATE_DELETE_LIMIT (a plain -D at C
    // compile time is not enough — compileoption_used can report 1 while the
    // parser still rejects LIMIT). Rewrite to the always-supported form:
    //   DELETE FROM t WHERE pk IN (SELECT pk FROM t WHERE … LIMIT n)
    final pkColumn = table.columns.firstWhere((c) => c.isPrimaryKey);
    final pkRef =
        '"${_escapeIdent(table.name)}"."${_escapeIdent(pkColumn.name)}"';
    final tableRef = '"${_escapeIdent(table.name)}"';
    final (innerWhereSql, params) = where.sql(table.name);
    final rewritten =
        '$pkRef IN (SELECT $pkRef FROM $tableRef WHERE $innerWhereSql LIMIT $limit)';
    return db.delete(from: schema).where(_sqlWithParams(rewritten, params));
  }

  rd.ToQuery<rd.Schema<R>, R> custom(
    String operation, {
    Where? where,
    List<Update> updates = const [],
  }) {
    throw UnimplementedError(
      'Custom operation has not been implemented: $operation',
    );
  }

  @override
  (String, List<Object?>) _translate(
    SqlDialect dialect,
    PerformOperationRequest request,
  ) {
    final query = _query(request);
    return dialect.translate(query);
  }

  /// Builds the [Query] for [request] so callers (e.g. [DbOperations]) can run
  /// [SqlDialect.translate] with the concrete schema row types for [S]/[R].
  Query<dynamic> _query(PerformOperationRequest request) {
    return switch (request) {
      CountOperationRequest(:final where) => count(where: where).compiled(),
      CreateOperationRequest(:final object) => insert(object).compiled(),
      CreateManyOperationRequest(:final objects) => insertMany([
        for (final object in objects) table.safeCreate(object),
      ]).compiled(),
      UpdateOperationRequest(:final where, :final updates) => update(
        updates,
        where: where,
      ).compiled(),
      DeleteOperationRequest(:final where, :final limit) => delete(
        where,
        limit: limit,
      ).compiled(),
      ReadOperationRequest(:final where) => list(
        limit: 1,
        where: where,
      ).compiled(),
      ListOperationRequest(
        :final where,
        :final limit,
        :final offset,
        :final orderBy,
        :final groupBy,
      ) =>
        list(
          where: where,
          limit: limit,
          offset: offset,
          orderBy: orderBy,
          groupBy: groupBy != null ? table[groupBy] : null,
        ).compiled(),
      CustomOperationRequest(:final where, :final operation, :final updates) =>
        custom(operation, where: where, updates: updates).compiled(),
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

/// Default CRUD operations for a collection with no custom operations file.
final class _DefaultTableOperations
    extends TableOperations<rd.Schema<Object?>, Object?> {
  _DefaultTableOperations(rd.Schema<Object?> schema) : super(schema);
}

/// Default auth operations for a collection with no custom operations file.
final class _DefaultAuthTableOperations
    extends TableOperations<AuthTable<Object?>, Object?>
    with AuthOperations<AuthTable<Object?>, Object?> {
  _DefaultAuthTableOperations(AuthTable<Object?> schema) : super(schema);
}

/// Builds default [TableOperations] for [schema] when no user-defined file exists.
TableOperations defaultOperationsFor(rd.Schema<Object?> schema) {
  if (schema is AuthTable<Object?>) {
    return _DefaultAuthTableOperations(schema);
  }
  return _DefaultTableOperations(schema);
}

base mixin AuthOperations<S extends AuthTable<R>, R> on TableOperations<S, R> {
  Future<Claims> addClaims({required Jwt jwt}) async {
    return Claims(jwt.claims);
  }

  /// Per-collection JWT lifetime override. `null` uses [AppConfig.jwtExpiresIn].
  Duration? get jwtExpiresIn => null;

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

class JwtConfig {
  const JwtConfig({
    required this.claims,
    required this.isAdmin,
    required this.canEdit,
    this.expiresIn,
  });

  factory JwtConfig.fromJson(Map<String, dynamic> json) {
    return JwtConfig(
      claims: Claims.fromJson(json['claims'] as Map<String, dynamic>),
      isAdmin: json['isAdmin'] as bool,
      canEdit: json['canEdit'] as bool,
      expiresIn: json['expiresIn'] == null
          ? null
          : Duration(seconds: json['expiresIn'] as int),
    );
  }

  final Claims claims;
  final bool isAdmin;
  final bool canEdit;

  /// When set, overrides [AppConfig.jwtExpiresIn] for this collection.
  final Duration? expiresIn;

  Map<String, dynamic> toJson() {
    return {
      'claims': claims.toJson(),
      'isAdmin': isAdmin,
      'canEdit': canEdit,
      'expiresIn': ?expiresIn?.inSeconds,
    };
  }
}

/// Default sort when a caller's `orderBy` is omitted: newest records first.
///
/// Prefers [CreatedAtTransformer] columns, then auto-increment primary keys,
/// then any primary key.
List<OrderByTerm>? _defaultOrderByFor(rd.TableMeta<dynamic, dynamic> table) {
  for (final column in table.columns) {
    if (column.transformer is CreatedAtTransformer) {
      return [OrderByTerm(column: column.name, direction: SortDirection.desc)];
    }
  }

  for (final column in table.columns) {
    if (column.isPrimaryKey && column.autoIncrement) {
      return [OrderByTerm(column: column.name, direction: SortDirection.desc)];
    }
  }

  for (final column in table.columns) {
    if (column.isPrimaryKey) {
      return [OrderByTerm(column: column.name, direction: SortDirection.desc)];
    }
  }

  return null;
}

/// Builds a parameterized [SQL] filter from a [Where] condition.
///
/// Values are bound as parameters (not inlined), so the DB driver handles
/// escaping. Column and table identifiers are double-quote escaped.
///
/// [tableName] qualifies every column reference; pass `null` for an
/// unqualified reference (see [WhereX.sql]).
SQL _whereFilter(Where where, String? tableName) {
  final (sql, params) = where.sql(tableName);
  return _sqlWithParams(sql, params);
}

SQL _sqlWithParams(String sql, List<Object?> params) {
  final parts = sql.split('?');
  final chunks = <Object?>[];
  for (var i = 0; i < parts.length; i++) {
    // trimRight: raindrop adds a separator space between chunks, so trailing
    // spaces in RawSQL parts would produce double-spaces before parameters.
    final part = parts[i].trimRight();
    if (part.isNotEmpty) chunks.add(RawSQL(part));
    if (i < params.length) chunks.add(params[i]);
  }
  return SQL(chunks);
}

String _escapeIdent(String name) => name.replaceAll('"', '""');

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
