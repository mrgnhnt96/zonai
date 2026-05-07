import 'package:scoped_deps/scoped_deps.dart';
import '../utils/args.dart';

final argsProvider = create<Args>(Args.new);

Args get args => read(argsProvider);
