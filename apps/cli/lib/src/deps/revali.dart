import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/db_mutator/revali.dart';

final revaliProvider = create<Revali>(Revali.new);

Revali get revali => read(revaliProvider);
