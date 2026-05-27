import 'package:zonai_playground/src/schemas/companies.dart';
import 'package:zonai_schema/zonai_schema.dart';

CompanyTableRules main() => CompanyTableRules();

final class CompanyTableRules
    extends TableRules<CompanyTable, Company> {
  CompanyTableRules() : super(companies);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  Future<bool> canUpdate(Jwt? jwt) async => true;

  Future<bool> canDelete(Jwt? jwt) async => true;

  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
}
