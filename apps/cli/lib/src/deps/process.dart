import 'package:io/io.dart';
import 'package:scoped_deps/scoped_deps.dart';

final processProvider = create<ProcessManager>(ProcessManager.new);

ProcessManager get process => read(processProvider);
