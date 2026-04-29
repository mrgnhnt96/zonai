import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/src/domain/settings.dart';

final settingsProvider = create<Settings>(Settings.load);

Settings get settings => read(settingsProvider);
