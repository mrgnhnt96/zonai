import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_schema/src/internal/tables.dart';
import 'package:zonai_schema/src/internal/abusers_table.dart' as schema;
import 'package:zonai_schema/src/internal/abusers_table.dart' hide AbusersTable;

class AbusersTable extends schema.AbusersTable {
  AbusersTable(super.$)
    : id = $.id(
        'id',
        (s) => s.id,
        fromString: AbuserId.new,
        generate: AbuserId.generate,
      ),
      ip = $.text('ip', (s) => s.ip),
      createdAt = $.createdAt('created_at', (s) => s.createdAt),
      report = $.enumerator('report', AbuseReport.values, (s) => s.report),
      blackListed = $.boolean('black_listed', (s) => s.blackListed),
      updatedAt = $.updatedAt('updated_at', (s) => s.updatedAt),
      blockedUntil = $.dateTime('blocked_until', (s) => s.blockedUntil);

  @override
  AbuserEntry fromRow(RowReader read) {
    return AbuserEntry(
      id: read(id),
      ip: read(ip),
      createdAt: read(createdAt),
      report: read(report),
      blackListed: read(blackListed),
      updatedAt: read(updatedAt),
      blockedUntil: read(blockedUntil),
    );
  }

  final IdColumn<AbuserId> id;
  final DateTimeColumn createdAt;
  final EnumColumn<AbuseReport> report;
  final TextColumn ip;
  final BooleanColumn blackListed;
  final ColumnType<DateTime?> updatedAt;
  final ColumnType<DateTime?> blockedUntil;
}

final abusers = () {
  final abusers = table('_abusers', AbusersTable.new);

  setupInternalTables(abusers: abusers);

  return abusers;
}();
