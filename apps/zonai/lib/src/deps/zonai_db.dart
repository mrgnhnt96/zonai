import 'package:scoped_deps/scoped_deps.dart';
import '../db_mutator/zonai_db/zonai_db.dart';

ZonaiDb? _db;

final zonaiDbProvider = create<ZonaiDb>(() => _db ??= ZonaiDb());

ZonaiDb get zonaiDB => read(zonaiDbProvider);
