import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_cli/src/utils/args.dart';

final argsProvider = create<Args>(Args.new);

Args get args => read(argsProvider);
