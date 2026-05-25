import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/versions.dart';

final versionsProvider = create<Versions>(() => const Versions());

Versions get versions => read(versionsProvider);
