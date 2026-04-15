import 'package:meta/meta.dart';
import 'package:raindrop/raindrop.dart' as rd;
import 'package:raindrop/raindrop.dart';
import 'false_delegate.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

part 'query_translator.dart';

/// Thin helpers around [rd.Raindrop] builders for a single [schema].
///
/// Each method returns a Raindrop builder. Builders are awaitable (they
/// implement [Future] via `ToQuery`), or you can chain more clauses and then
/// await. For row counts on update/delete, use [rd.Raindrop.execute] with
/// [rd.QueryBuilder.toQuery]; for `RETURNING`, use the SQLite extensions from
/// `package:raindrop_sqlite/raindrop_sqlite.dart` before awaiting.
abstract class CollectionOperations<T extends rd.Schema<T>> {
  CollectionOperations(this.schema);

  final T schema;

  static rd.Raindrop? __db;
  static rd.Raindrop get _db => __db ??= rd.Raindrop(FalseDelegate());

  @nonVirtual
  late rd.Raindrop db = _db;

  rd.InsertWithValuesBuilder<T, void> insert(T entity) =>
      db.insert(into: schema).values([entity]);

  rd.InsertWithValuesBuilder<T, void> insertMany(List<T> entities) =>
      db.insert(into: schema).values(entities);

  rd.UpdateSettingBuilder<T, void> update(List<Updateable<T>> updates) {
    final set = db.update(schema).set;

    return Function.apply(set, updates.take(19).toList()).returning();
  }

  /// [selectFrom] with optional filter and pagination applied first.
  rd.SelectFromBuilder<T, T> search({
    rd.Filter? where,
    int? limit,
    int? offset,
  }) {
    var builder = db.select().from(schema);
    if (where != null) {
      builder = builder.where(where);
    }

    if (limit != null) {
      builder = builder.limit(limit);
    }

    if (offset != null) {
      builder = builder.offset(offset);
    }

    return builder;
  }

  rd.DeleteAllBuilder<T, void> deleteAll() => db.delete(from: schema);

  rd.DeleteWhereBuilder<T, void> delete(Filter where) =>
      db.delete(from: schema).where(where);
}

mixin InsertReturning<T extends Schema<T>> on CollectionOperations<T> {
  rd.InsertWithValuesBuilder<T, T> insert(T entity) =>
      db.insert(into: schema).values([entity]).returning();
}

mixin UpdateReturning<T extends Schema<T>> on CollectionOperations<T> {
  rd.UpdateSettingBuilder<T, T> update(List<Updateable<T>> updates) {
    final set = db.update(schema).set;

    return Function.apply(set, updates.take(19).toList()).returning();
  }
}
