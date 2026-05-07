import 'package:scoped_deps/scoped_deps.dart';
import '../domain/stdin.dart';

final stdinProvider = create<Stdin>(Stdin.new);

Stdin get stdin => read(stdinProvider);
