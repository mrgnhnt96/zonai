import 'package:scoped_deps/scoped_deps.dart';
import '../domain/extensions/extensions.dart';

final extensionsProvider = create<Extensions>(Extensions.new);

Extensions get extensions => read(extensionsProvider);
