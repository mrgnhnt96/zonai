import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/schema_version/schema_version_check.dart';

final schemaVersionCheckProvider = create<SchemaVersionCheck>(() => const SchemaVersionCheck());

SchemaVersionCheck get schemaVersionCheck => read(schemaVersionCheckProvider);
