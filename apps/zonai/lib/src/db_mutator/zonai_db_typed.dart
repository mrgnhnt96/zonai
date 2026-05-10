import 'dart:async';

import 'package:raindrop/raindrop.dart' show Raindrop, Schema, Table;
import 'payloads/payloads.dart';
import 'zonai_db.dart' as impl;

/// Typed facade over [impl.ZonaiDb]: same behavior, but schema instances in/out.
class ZonaiDbTyped {
  ZonaiDbTyped() : _db = impl.ZonaiDb();

  final impl.ZonaiDb _db;

  Raindrop? get db => _db.db;

  Future<void> open() => _db.open();

  Future<(Object? error, T? result)> auth<T extends Schema<T>>(
    T tableRef,
    AuthPayload payload,
  ) async {
    final collection = Table.getFor(tableRef).name;
    final (err, row) = await _db.auth(collection, payload);
    if (err != null || row == null) return (err, null);
    return (null, _rowMapToSchema(tableRef, row));
  }

  Future<(Object? error, T? result)> create<T extends Schema<T>>(
    T object,
  ) async {
    final collection = Table.getFor(object).name;
    final (err, created) = await _db.create(
      collection,
      CreatePayload(object: _schemaInstanceToMap(object)),
    );
    if (err != null || created == null) return (err, null);
    return (null, _rowMapToSchema(object, created));
  }

  Future<(Object? error, List<T>? result)> update<T extends Schema<T>>(
    T tableRef,
    UpdatePayload payload,
  ) async {
    final collection = Table.getFor(tableRef).name;
    final (err, rows) = await _db.update(collection, payload);
    if (err != null || rows == null) return (err, null);
    return (null, _rowMapsToSchemas(tableRef, rows));
  }

  Future<(Object? error, int? result)> delete<T extends Schema<T>>(
    T tableRef,
    DeletePayload payload,
  ) {
    return _db.delete(Table.getFor(tableRef).name, payload);
  }

  Future<(Object? error, T? result)> view<T extends Schema<T>>(
    T tableRef,
    ViewPayload payload,
  ) async {
    final collection = Table.getFor(tableRef).name;
    final (err, row) = await _db.view(collection, payload);
    if (err != null) return (err, null);
    if (row == null) return (null, null);
    return (null, _rowMapToSchema(tableRef, row));
  }

  Future<(Object? error, List<T>? result)> list<T extends Schema<T>>(
    T tableRef,
    ListPayload payload,
  ) async {
    final collection = Table.getFor(tableRef).name;
    final (err, rows) = await _db.list(collection, payload);
    if (err != null || rows == null) return (err, null);
    return (null, _rowMapsToSchemas(tableRef, rows));
  }

  Stream<List<T>> streamList<T extends Schema<T>>(
    T tableRef,
    ListPayload payload,
  ) {
    final collection = Table.getFor(tableRef).name;
    return _db
        .streamList(collection, payload)
        .map((batch) => _rowMapsToSchemas(tableRef, batch));
  }

  Stream<T> streamOne<T extends Schema<T>>(T tableRef, ViewPayload payload) {
    final collection = Table.getFor(tableRef).name;
    return _db
        .streamOne(collection, payload)
        .map((row) => _rowMapToSchema(tableRef, row));
  }

  Map<String, dynamic> _schemaInstanceToMap<T extends Schema<T>>(T object) {
    final table = Table.getFor(object);
    return {
      for (final column in table.columns)
        column.name: column.encode(column.valueOf!(object)),
    };
  }

  T _rowMapToSchema<T extends Schema<T>>(T anchor, Map<String, Object?> raw) {
    return Table.getFor(anchor).create(Map<String, dynamic>.from(raw));
  }

  List<T> _rowMapsToSchemas<T extends Schema<T>>(
    T anchor,
    List<Map<String, Object?>> rows,
  ) {
    return rows.map((m) => _rowMapToSchema(anchor, m)).toList();
  }
}
