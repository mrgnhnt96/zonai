import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/db_mutator/zonai_db.dart';

final zonaiDbProvider = create<ZonaiDb>(ZonaiDb.new);

ZonaiDb get zonaiDB => read(zonaiDbProvider);
