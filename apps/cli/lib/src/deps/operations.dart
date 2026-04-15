import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_cli/src/domain/operations/operations.dart';

final operationsProvider = create<Operations>(Operations.new);

Operations get operations => read(operationsProvider);
