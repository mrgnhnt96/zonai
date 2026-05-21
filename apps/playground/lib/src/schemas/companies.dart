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

final class CompanyCollection extends Collection<Company> {
  CompanyCollection(super.$)
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
  final DateTimeColumn? updatedAt;
}

final companies = collection('companies', CompanyCollection.new);
