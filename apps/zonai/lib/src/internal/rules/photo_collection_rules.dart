import 'package:zonai/src/internal/photos_collection.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

PhotoCollectionRules main() => PhotoCollectionRules();

// TODO: figure out way for user to override these rules
base class PhotoCollectionRules
    extends InternalCollectionRules<PhotosCollection, PhotoEntry> {
  PhotoCollectionRules() : super(photos);

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;

  @override
  Future<bool> canView(Jwt? jwt) async => true;
}
