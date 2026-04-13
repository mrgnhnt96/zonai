import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_cli/src/domain/rules.dart';

final rulesProvider = create<Rules>(Rules.new);

Rules get rules => read(rulesProvider);
