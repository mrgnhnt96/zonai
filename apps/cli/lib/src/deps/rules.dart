import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/rules/rules.dart';

final rulesProvider = create<Rules>(Rules.new);

Rules get rules => read(rulesProvider);
