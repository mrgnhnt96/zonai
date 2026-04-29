import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/kill.dart';

final killProvider = create<Kill>(Kill.new);

Kill get kill => read(killProvider);
