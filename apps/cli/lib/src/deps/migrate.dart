import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_cli/src/domain/migrate.dart';

final migrateProvider = create<Migrate>(Migrate.new);

Migrate get migrate => read(migrateProvider);
