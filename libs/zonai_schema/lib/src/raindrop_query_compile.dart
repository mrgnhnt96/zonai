import 'package:zonai_schema/gen/raindrop/raindrop/dialect.dart';

/// Compiles a terminal Raindrop builder into a [Query] for SQL translation.
extension RaindropQueryCompile<S, V> on ToQuery<S, V> {
  // ignore: invalid_use_of_visible_for_testing_member
  Query<V> compiled() => compile();
}
