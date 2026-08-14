part of 'table_operations.dart';

/// Renders `"table"."column" AS "alias"`, overriding raindrop's automatic
/// `"table__column"` join alias (`SelectionClause`'s `singleTable: false`
/// branch — every projected column gets qualified *and* aliased that way
/// the moment a query has a join). raindrop's own `Column.as` produces a
/// `ColumnAlias` that carries alias info nothing in the rendering pipeline
/// actually reads (`SelectionClause`/`ExpressionClause` never look at
/// `ColumnAlias.alias`) — this renders the alias as literal SQL instead of
/// relying on it, and is a distinct name/type specifically so it doesn't
/// collide with (or get shadowed by) that existing instance method.
///
/// Required for [ViewQuery.query]/[ViewQuery.countQuery]: a view's raw SQL
/// result must come back keyed by the view's *own* declared column names
/// (`id`, `author_name`, ...), not `posts__id`/`authors__name`, or
/// `Table.safeCreate`/`fromRow` can't reconstruct a row for rules to see.
extension ViewColumnAlias on rd.Column<dynamic, dynamic> {
  rd.Expression<dynamic> aliasedAs(String alias) => _AliasedColumn(this, alias);
}

final class _AliasedColumn extends rd.Expression<dynamic> {
  _AliasedColumn(this._column, this._alias);

  final rd.Column<dynamic, dynamic> _column;
  final String _alias;

  @override
  rd.SQL build() =>
      rd.SQL([_column, rd.RawSQL('AS "${_alias.replaceAll('"', '""')}"')]);
}

/// The only thing a developer implements for a view — the query's shape.
///
/// [query] and [countQuery] should use raindrop's own select/join API
/// freely (columns, joins, aggregates) but must not apply `where`/`limit`/
/// `offset`/`orderBy` — [ViewOperations] applies those generically on top,
/// the same way a regular table's default `list()` does.
///
/// Every column [query] selects must be aliased with [ViewColumnAlias.aliasedAs]
/// to match [ViewOperations.schema]'s own declared column name exactly
/// (e.g. `authors.name.aliasedAs('author_name')`) — raindrop auto-aliases
/// joined columns as `"table__column"` otherwise, which won't match, and
/// rows won't reconstruct via `Table.safeCreate` the way every other
/// table's do.
///
/// **Filtering caveat**: a caller's `where`/`orderBy` reference columns by
/// the alias [query] selects them as. `ORDER BY` can reference a `.select`
/// alias (evaluated after the SELECT list), but `WHERE` generally cannot in
/// SQL (evaluated before it) — expose a column under its natural,
/// unambiguous source-table name if you want it filterable, not a renamed
/// alias.
abstract base class ViewQuery<R> {
  ViewQuery();

  /// Shared, non-executing query-builder handle — the same mechanism every
  /// table's operations already use to build (not run) SQL. Mutable (not
  /// `final`) so tests can point it at a real connection, the same way
  /// [TableOperations.db] is.
  late rd.Raindrop db = TableOperations._db;

  /// Columns + joins only — no where/limit/offset/orderBy.
  rd.SelectFromBuilder<dynamic, dynamic, dynamic> query();

  /// Same joins as [query], projecting a countable expression instead of
  /// the full column list (mirrors how a regular table's `count()` is
  /// already a separate query from `list()`, not derived from it).
  rd.SelectFromBuilder<dynamic, dynamic, dynamic> countQuery();
}

/// A read-only view over one or more tables.
///
/// Not extendable — `final` — so list/count/write-handling here can never
/// be overridden. A view's shape is defined by composing a [ViewQuery], not
/// by subclassing this.
final class ViewOperations<R> extends TableOperations<rd.Schema<R>, R> {
  ViewOperations(rd.Schema<R> schema, this.definition) : super(schema);

  final ViewQuery<R> definition;

  /// [ViewQuery.query] with a caller's filter/sort/pagination applied on
  /// top. Public (unlike [_translate]) so it's directly testable.
  rd.SelectFromBuilder<dynamic, dynamic, dynamic> compileList({
    Where? where,
    int? limit,
    int? offset,
    List<OrderByTerm>? orderBy,
  }) {
    var builder = definition.query();

    if (where != null) {
      builder = builder.where(_whereFilter(where, null));
    }

    final resolvedOrderBy = orderBy ?? _defaultOrderByFor(this.table);
    if (resolvedOrderBy != null && resolvedOrderBy.isNotEmpty) {
      builder = builder.orderBy({
        for (final term in resolvedOrderBy)
          _UnqualifiedColumn(term.column): term.direction == SortDirection.asc
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

    return builder;
  }

  /// [ViewQuery.countQuery] with a caller's filter applied on top.
  rd.SelectFromBuilder<dynamic, dynamic, dynamic> compileCount({Where? where}) {
    var builder = definition.countQuery();

    if (where != null) {
      builder = builder.where(_whereFilter(where, null));
    }

    return builder;
  }

  @override
  (String, List<Object?>) _translate(
    SqlDialect dialect,
    PerformOperationRequest request,
  ) {
    final query = switch (request) {
      ListOperationRequest(
        :final where,
        :final limit,
        :final offset,
        :final orderBy,
      ) =>
        compileList(
          where: where,
          limit: limit,
          offset: offset,
          orderBy: orderBy,
        ).compiled(),
      ReadOperationRequest(:final where) => compileList(
        where: where,
        limit: 1,
      ).compiled(),
      CountOperationRequest(:final where) => compileCount(
        where: where,
      ).compiled(),
      _ => throw UnsupportedError(
        '"${this.table.name}" is a view; write operations are not supported.',
      ),
    };

    return dialect.translate(query);
  }

  @override
  Never insert(Map<String, dynamic> data) => _rejectWrite();

  @override
  Never insertMany(List<R> entities) => _rejectWrite();

  @override
  Never update(List<Update> updates, {required Where where}) => _rejectWrite();

  @override
  Never delete(Where where, {int? limit}) => _rejectWrite();

  @override
  Never list({
    Where? where,
    int? limit,
    int? offset,
    List<OrderByTerm>? orderBy,
    Selectable<dynamic>? groupBy,
  }) => throw UnsupportedError(
    '"${this.table.name}" is a view; use compileList instead of list.',
  );

  @override
  Never count({Where? where}) => throw UnsupportedError(
    '"${this.table.name}" is a view; use compileCount instead of count.',
  );

  Never _rejectWrite() => throw UnsupportedError(
    '"${this.table.name}" is a view; write operations are not supported.',
  );
}

/// A bare `"column"` reference with no table qualifier.
///
/// [ViewOperations.compileList]'s default/explicit `ORDER BY` can't qualify
/// with the view's own (non-existent-in-SQL) table name the way a regular
/// table's `list()` qualifies with a real one — the joined query has no
/// `FROM`/`JOIN` target by that name. An unqualified reference resolves
/// against [ViewQuery.query]'s own SELECT list (aliases are visible to
/// `ORDER BY`, unlike `WHERE`) or an unambiguous underlying column.
final class _UnqualifiedColumn extends rd.Expression<dynamic> {
  _UnqualifiedColumn(this._name);

  final String _name;

  @override
  rd.SQL build() => rd.SQL([rd.RawSQL('"${_name.replaceAll('"', '""')}"')]);
}
