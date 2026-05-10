import 'package:scoped_deps/scoped_deps.dart';
import '../db_mutator/zonai_db.dart';

// TODO(mrgnhnt): Update all other dependencies that need to be singletons to
// follow this pattern (as opposed to an static instance)
ZonaiDb? _db;

final zonaiDbProvider = create<ZonaiDb>(() => _db ??= ZonaiDb());

ZonaiDb get zonaiDB => read(zonaiDbProvider);
