import 'package:scoped_deps/scoped_deps.dart';
import '../domain/rules/rules.dart';

final rulesProvider = create<Rules>(Rules.new);

Rules get rules => read(rulesProvider);
