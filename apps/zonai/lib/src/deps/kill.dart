import 'package:scoped_deps/scoped_deps.dart';
import '../domain/kill.dart';

Kill? _kill;

final killProvider = create<Kill>(() => _kill ??= Kill());

Kill get kill => read(killProvider);
