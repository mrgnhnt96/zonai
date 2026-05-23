import 'package:file/file.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/domain/constants.dart';

class Env {
  Env();

  Map<String, String>? _items;

  List<String> get dartDefineArgs {
    Iterable<String> items() sync* {
      for (final MapEntry(:key, :value) in this.items.entries) {
        yield '$key=$value';
      }
    }

    final defines = items().toList();
    if (defines.isEmpty) {
      return const [];
    }

    return ['-D${defines.join(',')}'];
  }

  Map<String, String> get items {
    if (_items case final items? when kIsCompiled) {
      return Map.unmodifiable(items);
    }

    final flavor = args.getOrNull<String>('flavor');

    final baseEnv = fs.file('.env');
    final hasBaseEnv = baseEnv.existsSync();
    if (!hasBaseEnv && flavor == null) {
      return {};
    }

    File? flavorEnv;

    if (flavor case final flavor?) {
      flavorEnv = fs.file('.env.${flavor}');
      final hasFlavorEnv = flavorEnv.existsSync();
      if (!hasFlavorEnv) {
        logger.warn(
          'No flavor-specific .env file found for flavor: $flavor (expected path: ${flavorEnv.path})',
        );

        if (!hasBaseEnv) {
          return {};
        }
      }
    }

    final env = switch ((baseEnv, flavorEnv)) {
      (_, final env?) when env.existsSync() => env,
      (final base, _) when base.existsSync() => base,
      _ => null,
    };

    if (env == null) {
      return {};
    }

    final items = <String, String>{};

    final lines = env.readAsLinesSync();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final firstEqual = trimmed.indexOf('=');
      if (firstEqual == -1) continue;

      final key = trimmed.substring(0, firstEqual);
      final value = trimmed.substring(firstEqual + 1);

      if (key.isEmpty) continue;

      items[key] = value;
    }

    return _items = Map.unmodifiable(items);
  }
}
