import 'package:zonai_schema/src/payloads/parse_body.dart';

/// Query metadata for `POST /photos` (create).
///
/// The image itself is sent as the raw request body (`application/octet-stream`
/// or an `image/*` type). Set [HttpHeaders.contentTypeHeader] on the request;
/// the server verifies the mime type when handling the upload.
class PhotoCreateMeta {
  const PhotoCreateMeta({required this.table});

  /// Target collection the photo is attached to.
  final String table;

  factory PhotoCreateMeta.fromJson(Map<String, dynamic> json) =>
      parseBody('PhotoCreateMeta', () => PhotoCreateMeta._fromJson(json));

  factory PhotoCreateMeta._fromJson(Map<String, dynamic> json) {
    return PhotoCreateMeta(table: json['table'] as String);
  }

  Map<String, dynamic> toJson() => {'table': table};
}
