import '../types/where.dart';
import '../update/update.dart';

/// The operation name itself travels on the URL (`PATCH /db/custom/:operation`),
/// not in this body — `table` still comes from the body like every other
/// `/db` payload. `where` is nullable — unlike [UpdateBody], a custom
/// operation may be table-scoped with no target rows (e.g. an administrative
/// action), so there's no row to check or write. [CustomOneBody] requires it
/// (a singular call always targets exactly one row).
class CustomBody {
  const CustomBody({
    required this.table,
    this.where,
    this.limit,
    this.updates = const [],
  });

  final String table;
  final Where? where;
  final int? limit;
  final List<Update> updates;

  factory CustomBody.fromJson(Map<String, dynamic> json) {
    return CustomBody(
      table: json['table'] as String,
      where: switch (json['where']) {
        final Map<String, dynamic> where => Where.fromJson(where),
        _ => null,
      },
      limit: json['limit'] as int?,
      updates: [
        for (final update in json['updates'] as List? ?? const [])
          Update.fromJson(update as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'table': table,
      'where': ?where?.toJson(),
      'limit': ?limit,
      'updates': [for (final update in updates) update.toJson()],
    };
  }
}

class CustomOneBody extends CustomBody {
  const CustomOneBody({
    required String table,
    required Where where,
    List<Update> updates = const [],
  }) : super(table: table, where: where, limit: 1, updates: updates);

  factory CustomOneBody.fromJson(Map<String, dynamic> json) {
    return CustomOneBody(
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      updates: [
        for (final update in json['updates'] as List? ?? const [])
          Update.fromJson(update as Map<String, dynamic>),
      ],
    );
  }
}
