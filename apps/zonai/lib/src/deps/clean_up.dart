import 'package:scoped_deps/scoped_deps.dart';
import '../domain/clean_up.dart';

CleanUp? _cleanUp;

final cleanUpProvider = create<CleanUp>(() => _cleanUp ??= CleanUp());

CleanUp get cleanUp => read(cleanUpProvider);
