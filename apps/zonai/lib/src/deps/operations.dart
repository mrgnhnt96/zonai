import 'package:scoped_deps/scoped_deps.dart';
import '../domain/operations/operations.dart';

Operations? _operations;

final operationsProvider = create<Operations>(
  () => _operations ??= Operations(),
);

Operations get operations => read(operationsProvider);
