import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/zonai_schema.dart';

PhotoCollectionRules main() => PhotoCollectionRules();

final class PhotoCollectionRules
    extends InternalCollectionRules<PhotosCollection, PhotoEntry> {
  PhotoCollectionRules() : super(photos, canBeOverridden: true);

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;

  @override
  Future<bool> canView(Jwt? jwt) async => true;
}
