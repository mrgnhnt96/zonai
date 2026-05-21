import 'package:zonai_playground/src/schemas/companies.dart';
import 'package:zonai_schema/zonai_schema.dart';

CompanyRecordRules main() => CompanyRecordRules();

class CompanyRecordRules extends RecordRules<CompanyCollection, Company> {
  CompanyRecordRules() : super(companies);

  @override
  Future<bool> canView(Jwt? jwt, Company record) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Company record) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Company record) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Company record) async => true;
}
