import 'package:resqlite/resqlite.dart' as rs;
import 'package:zonai/src/db_mutator/zonai_db/resqlite/sql_read_dependencies.dart';

const queries = [
  'SELECT "id", "name", "created_at", "updated_at" FROM "items" ORDER BY "created_at" DESC LIMIT 10 OFFSET 5',
  'SELECT "id", "name", "created_at", "updated_at" FROM "items" WHERE "items"."id" = \$1 ORDER BY "created_at" DESC LIMIT 1',
  'SELECT COUNT("id") FROM "items" WHERE "items"."id" = \$1',
  'SELECT "id" FROM "items" WHERE "items"."id" = \$1',
  'SELECT "id" FROM "items" WHERE "id" = \$1',
  'SELECT "id" FROM "items" WHERE 1 = \$1',
  'SELECT "id" FROM "items" WHERE "items"."id" = 1',
];

String describe(rs.TableDependencies deps) {
  return switch (deps) {
    rs.UnknownTableDependencies() => 'UNKNOWN',
    rs.FixedTableDependencies(:final tables) =>
      'FIXED(${tables.map((t) => t.table).join(", ")})',
  };
}

void main() {
  for (final sql in queries) {
    print('${describe(readDependenciesForStreamSql(sql))}  <=  $sql');
  }
}
