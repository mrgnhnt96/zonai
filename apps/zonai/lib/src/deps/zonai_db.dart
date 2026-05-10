import 'package:scoped_deps/scoped_deps.dart';
import '../db_mutator/zonai_db.dart';

// TODO(mrgnhnt): Update all other dependencies that need to be singletons to
// follow this pattern (as opposed to an static instance)
late final _db = ZonaiDb();

final zonaiDbProvider = create<ZonaiDb>(() => _db);

ZonaiDb get zonaiDB => read(zonaiDbProvider);
