import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_cli/src/domain/process.dart';

final processProvider = create<Process>(Process.new);

Process get process => read(processProvider);
