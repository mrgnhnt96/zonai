import 'package:raindrop/raindrop.dart';

/// A [Filter] backed by a raw SQL predicate (no parameter binding).
///
/// Only use with trusted SQL. User-controlled strings belong in [SQL] chunks
/// that are translated as bound parameters, not in [RawSQL].
class RawSqlFilter extends SQL {
  RawSqlFilter(String sql) : super([RawSQL(sql)]);
}
