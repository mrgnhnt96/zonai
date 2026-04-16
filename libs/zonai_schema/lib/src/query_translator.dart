part of 'collection_operations.dart';

class QueryTranslator<T extends Schema<T>> {
  QueryTranslator();

  (String, List<Object?>) translate(ToQuery query) {
    final translate = const SQLiteDialect().translate;

    return switch (query.toQuery()) {
      final Insert<T, T?> q => translate(q),
      final Insert<T, void> q => translate(q),
      final Select<T, T?> q => translate(q),
      final Update<T, T?> q => translate(q),
      final Update<T, void> q => translate(q),
      final Delete<T, T?> q => translate(q),
      final Delete<T, void> q => translate(q),
      _ => throw UnsupportedError('Not a translatable query: $query'),
    };
  }
}
