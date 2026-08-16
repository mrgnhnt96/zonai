import 'package:zonai_playground/src/schemas/companies.dart';
import 'package:zonai_schema/zonai_schema.dart';

CompanyRowRules main() => CompanyRowRules();

/// Every company row is readable; writes fall through to `BaseRowRules`,
/// which allows them only for a JWT carrying `admin.canEdit`.
class CompanyRowRules extends RowRules<CompanyTable, Company> {
  CompanyRowRules() : super(companies);

  @override
  Future<bool> canView(Jwt? jwt, Company row) async => true;
}
