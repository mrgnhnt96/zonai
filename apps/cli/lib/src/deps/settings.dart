import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_cli/src/domain/settings.dart';

final settingsProvider = create<Settings>(Settings.load);

Settings get settings => read(settingsProvider);
