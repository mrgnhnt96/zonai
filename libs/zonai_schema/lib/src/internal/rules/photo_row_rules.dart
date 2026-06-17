import 'package:zonai_schema/src/internal/tables/photos_table.dart';
import 'package:zonai_schema/src/rules/rules.dart';
import 'package:zonai_schema/zonai_schema.dart' hide photos, PhotosTable;

PhotoRowRules main() => PhotoRowRules();

final class PhotoRowRules extends InternalRowRules<PhotosTable, PhotoEntry> {
  PhotoRowRules() : super(photos, canBeOverridden: true);

  @override
  Future<bool> canView(Jwt? jwt, PhotoEntry row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, PhotoEntry row) async {
    if (jwt == null) return false;
    if (jwt.admin.isAdmin) return true;
    if (jwt.userId == row.ownerId) return true;

    return false;
  }

  @override
  Future<bool> canDelete(Jwt? jwt, PhotoEntry row) async {
    if (jwt == null) return false;
    if (jwt.admin.isAdmin) return true;
    if (jwt.userId == row.ownerId) return true;

    return false;
  }

  @override
  Future<bool> canCreate(Jwt? jwt, PhotoEntry row) async {
    return jwt != null;
  }
}
