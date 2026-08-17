import 'package:zonai_playground/src/schemas/companies.dart';
import 'package:zonai_schema/zonai_schema.dart';

CompanyTableRules main() => CompanyTableRules();

/// Companies are shared reference data: everyone reads them, only an admin
/// writes them.
///
/// The write methods are deliberately NOT overridden. `BaseTableRules`
/// already denies `canCreate`/`canUpdate`/`canDelete` to anyone without
/// `jwt.admin.canEdit`, so writing them out would only restate the default
/// and give the next reader something to accidentally relax.
final class CompanyTableRules extends TableRules<CompanyTable, Company> {
  CompanyTableRules() : super(companies);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  @override
  Future<bool> canList(Jwt? jwt) async => true;
}
