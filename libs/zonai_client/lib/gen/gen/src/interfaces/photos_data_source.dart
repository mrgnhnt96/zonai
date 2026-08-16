part of '../../interfaces.dart';

abstract interface class PhotosDataSource {
  const PhotosDataSource();

  Stream<List<int>> view({required String id, String? authorization});
  Future<Map<String, Object?>> create({
    required Stream<List<int>> image,
    required PhotoCreateMeta meta,
    String? authorization,
    String? contentType,
  });
  Future<void> update({
    required String id,
    required Stream<List<int>> image,
    String? authorization,
  });
  Future<void> delete({required String id, String? authorization});
}
