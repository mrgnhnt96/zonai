import 'package:scoped_deps/scoped_deps.dart';
import '../domain/rules/rules.dart';

Rules? _rules;

final rulesProvider = create<Rules>(() => _rules ??= Rules());

Rules get rules => read(rulesProvider);
