import 'package:zonai/src/internal/photos_collection.dart';
import 'package:zonai_schema/zonai_schema.dart';

PhotoExtension main() => PhotoExtension();

final class PhotoExtension extends Extension<PhotoEntry> {
  PhotoExtension() : super(photos);

  @override
  Future<void> beforeCreate(PhotoEntry object, Jwt? jwt) async {
    logger.debug('EXTENSION beforeCreate');
  }

  @override
  Future<void> afterDeleteSuccess(PhotoEntry object, Jwt? jwt) async {
    // TODO: delete the photo from the filesystem
  }
}
