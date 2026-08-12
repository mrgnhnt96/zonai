import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart';

/// File name a project drops into `imagesPath` to replace the letter tile.
///
/// The URL it is served from lives in `providers/brand_logo_provider.dart`,
/// which the client can import; this library cannot, since `package:zonai`
/// pulls in `dart:io`.
const brandLogoFileName = 'logo.png';

/// Whether the project ships a custom brand mark at `<imagesPath>/logo.png`.
///
/// Checked per SSR render so dropping the file in takes effect on reload,
/// without a restart.
Future<bool> loadHasBrandLogo() {
  return runMergedScopedFuture(
    () async => fs.file(fs.path.join(settings.imagesPath, brandLogoFileName)).existsSync(),
    // Narrower than the sibling loaders here on purpose: this reads a path off
    // [Settings] and stats a file, so it never reaches the config worker or
    // the DB.
    includeIfAbsent: {
      argsProvider,
      loggerProvider,
      fsProvider,
      settingsProvider.overrideWith(() {
        if (kIsCompiled) {
          return Settings.load();
        }
        return Settings.load(fs.path.join('..', 'playground'));
      }),
    },
  );
}
