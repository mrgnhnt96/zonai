import 'package:zonai_schema/zonai_schema.dart';

class AbuserEntry {
  const AbuserEntry({
    required this.id,
    required this.ip,
    required this.report,
    required this.createdAt,
    required this.blackListed,
    required this.updatedAt,
    required this.blockedUntil,
  });

  final AbuserId id;
  final String ip;
  final AbuseReport report;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool blackListed;
  final DateTime? blockedUntil;
}

enum AbuseReport { suspiciousActivity, spam, bruteForce, other }

class AbuserId implements Id {
  AbuserId(this.value) {
    if (!value.endsWith(_suffix)) {
      throw ArgumentError.value(value, 'value', 'Value must end with $_suffix');
    }
  }

  factory AbuserId.fromJson(String value) => AbuserId(value);

  static AbuserId generate() => AbuserId(Id.generate(_suffix));

  static const _suffix = 'ab';

  @override
  final String value;

  String toJson() => value;
}

class AbusersTable extends Table<AbuserEntry> {
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

final abusers = table('_abusers', AbusersTable.new);
