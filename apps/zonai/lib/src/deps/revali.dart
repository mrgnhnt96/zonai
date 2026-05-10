import 'package:scoped_deps/scoped_deps.dart';
import '../db_mutator/revali.dart';

Revali? _revali;

final revaliProvider = create<Revali>(() => _revali ??= Revali());

Revali get revali => read(revaliProvider);
