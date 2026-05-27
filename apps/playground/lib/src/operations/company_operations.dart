import 'package:zonai_playground/src/schemas/companies.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class CompanyOperations
    extends TableOperations<CompanyTable, Company> {
  CompanyOperations() : super(companies);
}

CompanyOperations main() => CompanyOperations();
