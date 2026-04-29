import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/clean_up.dart';

final cleanUpProvider = create<CleanUp>(CleanUp.new);

CleanUp get cleanUp => read(cleanUpProvider);
