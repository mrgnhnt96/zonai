import 'package:zonai/src/internal/photos_collection.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/src/types/jwt.dart';

PhotoRecordRules main() => PhotoRecordRules();

// TODO: figure out way for user to override these rules
base class PhotoRecordRules
    extends InternalRecordRules<PhotosCollection, PhotoEntry> {
  PhotoRecordRules() : super(photos);

  @override
  Future<bool> canView(Jwt? jwt, PhotoEntry record) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, PhotoEntry record) async {
    if (jwt == null) return false;
    if (jwt.admin.isAdmin) return true;
    if (jwt.userId == record.ownerId) return true;

    return false;
  }

  @override
  Future<bool> canDelete(Jwt? jwt, PhotoEntry record) async {
    if (jwt == null) return false;
    if (jwt.admin.isAdmin) return true;
    if (jwt.userId == record.ownerId) return true;

    return false;
  }

  @override
  Future<bool> canCreate(Jwt? jwt, PhotoEntry record) async {
    return jwt != null;
  }
}
