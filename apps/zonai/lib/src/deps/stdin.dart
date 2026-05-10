import 'package:scoped_deps/scoped_deps.dart';
import '../domain/stdin.dart';

Stdin? _stdin;

final stdinProvider = create<Stdin>(() => _stdin ??= Stdin());

Stdin get stdin => read(stdinProvider);
