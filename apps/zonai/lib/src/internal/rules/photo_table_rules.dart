import 'package:zonai/src/internal/photos_table.dart';
import 'package:zonai/src/internal/rules/internal_rules.dart';
import 'package:zonai_schema/zonai_schema.dart' hide photos, PhotosTable;

PhotoTableRules main() => PhotoTableRules();

final class PhotoTableRules
    extends InternalTableRules<PhotosTable, PhotoEntry> {
  PhotoTableRules() : super(photos, canBeOverridden: true);

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt) async => true;

  @override
  Future<bool> canView(Jwt? jwt) async => true;
}
