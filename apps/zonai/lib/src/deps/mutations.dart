import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/mutations.dart';

final mutationsProvider = create<Mutations>(() => Mutations(track: false));

Mutations get mutations => read(mutationsProvider);
