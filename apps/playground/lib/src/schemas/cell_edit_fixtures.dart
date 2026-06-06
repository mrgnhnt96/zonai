import 'package:raindrop/raindrop.dart' show ReferentialAction;
import 'package:zonai_playground/src/ids.dart';
import 'package:zonai_schema/zonai_schema.dart';

import 'companies.dart';

enum FixtureStatus { draft, published, archived }

enum FixtureTag { alpha, beta, gamma }

final class CellEditFixture {
  CellEditFixture({
    required this.id,
    required this.label,
    required this.flag,
    required this.count,
    required this.amount,
    required this.bigCount,
    required this.happenedAt,
    required this.contactEmail,
    required this.status,
    required this.tags,
    required this.keywords,
    required this.secretNote,
    required this.meta,
    required this.createdAt,
    this.companyId,
    this.payload,
    this.updatedAt,
  });

  final CellEditFixturesId id;
  final String label;
  final bool flag;
  final int count;
  final double amount;
  final BigInt bigCount;
  final DateTime happenedAt;
  final String contactEmail;
  final FixtureStatus status;
  final List<FixtureTag> tags;
  final List<String> keywords;
  final CompaniesId? companyId;
  final String secretNote;
  final Map<String, dynamic> meta;
  final List<int>? payload;
  final DateTime createdAt;
  final DateTime? updatedAt;
}

final class CellEditFixtureTable extends Table<CellEditFixture> {
  CellEditFixtureTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: CellEditFixturesId.new,
        generate: CellEditFixturesId.generate,
      ),
      label = $.text('label', (s) => s.label),
      flag = $.boolean('flag', (s) => s.flag),
      count = $.integer('count', (s) => s.count),
      amount = $.real('amount', (s) => s.amount),
      bigCount = $.bigInt('big_count', (s) => s.bigCount),
      happenedAt = $.dateTime('happened_at', (s) => s.happenedAt),
      contactEmail = $.email('contact_email', (s) => s.contactEmail),
      status = $.enumerator('status', FixtureStatus.values, (s) => s.status),
      tags = $.enumList('tags', FixtureTag.values, (s) => s.tags),
      keywords = $.list(
        'keywords',
        (s) => s.keywords,
        fromJson: (e) => switch (e) {
          String() => e,
          _ => '$e',
        },
      ),
      companyId = $
          .id(
            'company_id',
            (s) => s.companyId,
            fromString: CompaniesId.new,
            generate: CompaniesId.generate,
            isPrimaryKey: false,
          )
          .references(() => companies.id, onDelete: ReferentialAction.setNull),
      secretNote = $.password('secret_note', (s) => s.secretNote),
      meta = $.map('meta', (s) => s.meta),
      payload = $.blob('payload', (s) => s.payload),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt);

  @override
  CellEditFixture fromRow(RowReader read) {
    return CellEditFixture(
      id: read(id),
      label: read(label),
      flag: read(flag),
      count: read(count),
      amount: read(amount),
      bigCount: read(bigCount),
      happenedAt: read(happenedAt),
      contactEmail: read(contactEmail),
      status: read(status),
      tags: read(tags),
      keywords: read(keywords),
      companyId: read(companyId),
      secretNote: read(secretNote),
      meta: read(meta),
      payload: read(payload),
      createdAt: read(createdAt),
      updatedAt: read(updatedAt),
    );
  }

  final IdColumn<CellEditFixturesId> id;
  final TextColumn label;
  final BooleanColumn flag;
  final IntColumn count;
  final RealColumn amount;
  final BigIntColumn bigCount;
  final DateTimeColumn happenedAt;
  final EmailColumn contactEmail;
  final EnumColumn<FixtureStatus> status;
  final EnumListColumn<FixtureTag> tags;
  final ListColumn<String> keywords;
  final IdColumn<CompaniesId>? companyId;
  final PasswordColumn secretNote;
  final MapColumn meta;
  final BlobColumn? payload;
  final DateTimeColumn createdAt;
  final DateTimeColumn? updatedAt;
}

final cellEditFixtures = table('cell_edit_fixtures', CellEditFixtureTable.new);
