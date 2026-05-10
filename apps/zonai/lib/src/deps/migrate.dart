import 'package:scoped_deps/scoped_deps.dart';
import '../domain/migrate.dart';

Migrate? _migrate;

final migrateProvider = create<Migrate>(() => _migrate ??= Migrate());

Migrate get migrate => read(migrateProvider);
