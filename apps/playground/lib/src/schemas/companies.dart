import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class Company {
  Company({
    required this.id,
    required this.name,
    required this.createdAt,
    this.updatedAt,
  });

  final CompaniesId id;
  final String name;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class CompanyTable extends Table<Company> {
  CompanyTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: CompaniesId.new,
        generate: CompaniesId.generate,
      ),
      name = $.text('name', (s) => s.name),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  Company fromRow(RowReader read) {
    return Company(
      id: read(id),
      name: read(name),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<CompaniesId> id;
  final TextColumn name;
  final DateTimeColumn createdAt;
  final ColumnType<DateTime?> updatedAt;
}

final companies = table('companies', CompanyTable.new);
