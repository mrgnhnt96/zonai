import 'package:scoped_deps/scoped_deps.dart';
import '../domain/cron/crons.dart';

CronsCompiler? _crons;

final cronsProvider = create<CronsCompiler>(() => _crons ??= CronsCompiler());

CronsCompiler get cronsCompiler => read(cronsProvider);
