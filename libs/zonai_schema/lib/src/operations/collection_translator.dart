part of 'collection_operations.dart';

class CollectionTranslator {
  CollectionTranslator(this.collection, this.dialect);

  final _DbCollection collection;
  final BaseSqlDialect dialect;

  (String, List<Object?>) translate(PerformOperationRequest request) {
    return collection._translate(dialect, request);
  }
}
