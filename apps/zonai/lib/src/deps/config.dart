import 'package:scoped_deps/scoped_deps.dart';
import '../domain/config/config.dart';

Config? _config;

final configProvider = create<Config>(() => _config ??= Config());

Config get config => read(configProvider);
