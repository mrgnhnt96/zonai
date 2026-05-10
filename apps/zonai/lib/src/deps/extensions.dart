import 'package:scoped_deps/scoped_deps.dart';
import '../domain/extensions/extensions.dart';

Extensions? _extensions;

final extensionsProvider = create<Extensions>(
  () => _extensions ??= Extensions(),
);

Extensions get extensions => read(extensionsProvider);
