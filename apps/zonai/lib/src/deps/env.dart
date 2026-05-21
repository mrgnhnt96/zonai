import 'package:scoped_deps/scoped_deps.dart';
import '../domain/env.dart';

Env? _env;

final envProvider = create<Env>(() => _env ??= Env());

Env get env => read(envProvider);
