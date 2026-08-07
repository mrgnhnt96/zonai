import 'package:zonai_playground/src/schemas/companies.dart';
import 'package:zonai_schema/zonai_schema.dart';

CompanyRowRules main() => CompanyRowRules();

class CompanyRowRules extends RowRules<CompanyTable, Company> {
  CompanyRowRules() : super(companies);

  @override
  Future<bool> canView(Jwt? jwt, Company row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Company before, Company after) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Company row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Company row) async => true;
}
