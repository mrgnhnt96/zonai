import 'package:zonai/src/internal/photos_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/zonai_schema.dart' hide photos, PhotosTable;

PhotoRecordRules main() => PhotoRecordRules();

final class PhotoRecordRules
    extends InternalRecordRules<PhotosTable, PhotoEntry> {
  PhotoRecordRules() : super(photos, canBeOverridden: true);

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
