part of '../../interfaces.dart';

abstract interface class ApiTokenDataSource {
  const ApiTokenDataSource();

  Future<Map<String, Object?>> list({String? authorization});
  Future<Map<String, Object?>> create({
    required ApiTokenCreateBody body,
    String? authorization,
  });
  Future<Map<String, Object?>> revoke({
    required String id,
    String? authorization,
  });
  Future<void> delete({required String id, String? authorization});
}
