import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/stdin.dart';

final stdinProvider = create<Stdin>(Stdin.new);

Stdin get stdin => read(stdinProvider);
