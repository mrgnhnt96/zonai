import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:zonai_schema/src/column_types/enum_column.dart';
import 'package:zonai_schema/src/column_types/id_column.dart';
import 'package:zonai_schema/src/schemas/table.dart';
import 'package:zonai_schema/src/types/id.dart';

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

abstract class AbusersTable extends Table<AbuserEntry> {
  AbusersTable(super.$);

  IdColumn<AbuserId> get id;
  DateTimeColumn get createdAt;
  EnumColumn<AbuseReport> get report;
  TextColumn get ip;
  BooleanColumn get blackListed;
  DateTimeColumn? get updatedAt;
  DateTimeColumn? get blockedUntil;
}
