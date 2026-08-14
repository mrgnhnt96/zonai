import 'package:zonai_client/gen/interfaces.dart';
import 'package:zonai_schema/payloads.dart';

class Photos {
  const Photos({required this._photos});

  final PhotosDataSource _photos;

  Stream<List<int>> get({required String id, String? authorization}) {
    return _photos.view(id: id, authorization: authorization);
  }

  Future<Map<String, Object?>> create({
    required Stream<List<int>> image,
    required PhotoCreateMeta meta,
    String? authorization,
    String? contentType,
  }) async {
    return await _photos.create(
      image: image,
      meta: meta,
      authorization: authorization,
      contentType: contentType,
    );
  }

  Future<void> update({
    required Stream<List<int>> image,
    required String id,
    String? authorization,
    String? contentType,
  }) async {
    await _photos.update(image: image, id: id, authorization: authorization);
  }

  Future<void> delete({required String id, String? authorization}) async {
    await _photos.delete(id: id, authorization: authorization);
  }
}
