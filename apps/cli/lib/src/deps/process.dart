import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/process.dart';

final processProvider = create<Process>(Process.new);

Process get process => read(processProvider);
