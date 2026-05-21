import 'package:scoped_deps/scoped_deps.dart';
import '../domain/executable_stop.dart';

ExecutableStop? _executableStop;

final executableStopProvider = create<ExecutableStop>(
  () => _executableStop ??= ExecutableStop(),
);

ExecutableStop get executableStop => read(executableStopProvider);
