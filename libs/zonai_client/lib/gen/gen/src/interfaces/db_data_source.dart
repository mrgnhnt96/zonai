part of '../../interfaces.dart';

abstract interface class DbDataSource {
  const DbDataSource();

  Future<Map<String, Object?>> get({
    required GetBody body,
    String? authorization,
  });
  Future<Map<String, Object?>> list({
    required ListBody body,
    String? authorization,
  });
  Future<int> count({required CountBody body, String? authorization});
  Stream<Map<String, Object?>> streamOne({
    required StreamBody body,
    String? authorization,
  });
  Stream<List<Map<String, Object?>>> streamList({
    required StreamListBody body,
    String? authorization,
  });
  Stream<int> streamCount({
    required StreamCountBody body,
    String? authorization,
  });
  Future<Map<String, Object?>> create({
    required CreateBody body,
    String? authorization,
  });
  Future<List<Map<String, Object?>>> createMany({
    required CreateManyBody body,
    String? authorization,
  });
  Future<Map<String, Object?>> update({
    required UpdateOneBody body,
    String? authorization,
  });
  Future<List<Map<String, Object?>>> updateMany({
    required UpdateBody body,
    String? authorization,
  });
  Future<Map<String, Object?>> custom({
    required String operation,
    required CustomOneBody body,
    String? authorization,
  });
  Future<List<Map<String, Object?>>> customMany({
    required String operation,
    required CustomBody body,
    String? authorization,
  });
  Future<void> delete({required DeleteOneBody body, String? authorization});
  Future<void> deleteMany({required DeleteBody body, String? authorization});
}
