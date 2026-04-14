import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_cli/src/domain/extensions/extensions.dart';

final extensionsProvider = create<Extensions>(Extensions.new);

Extensions get extensions => read(extensionsProvider);
