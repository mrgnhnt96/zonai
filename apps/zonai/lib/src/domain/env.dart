import 'dart:async';

import 'package:file/file.dart';
import 'package:watcher/watcher.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/domain/constants.dart';

String parseEnvValue(String raw) {
  final value = raw.trim();
  if (value.length >= 2) {
    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}

class Env {
  Env();

  DirectoryWatcher? __watcher;
  DirectoryWatcher get _watcher =>
      __watcher ??= DirectoryWatcher(env.file.path);

  StreamSubscription<WatchEvent>? __subscription;

  Map<String, String>? _items;

  void watch(void Function() onChange) {
    if (args.release) return;
    if (__subscription != null) return;

    if (!env.exists) return;

    __subscription = _watcher.events.listen((event) {
      logger.debug('Env changed: ${event.path}');
      onChange();
    });

    cleanUp.add(stop);
  }

  void stop() {
    __subscription?.cancel();
    __subscription = null;
  }

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

  ({File file, bool exists}) get env {
    final flavor = args.getOrNull<String>('flavor');

    final baseEnv = fs.file('.env');
    final hasBaseEnv = baseEnv.existsSync();
    if (flavor == null) {
      return (file: baseEnv, exists: hasBaseEnv);
    }

    File? flavorEnv;

    flavorEnv = fs.file('.env.${flavor}');
    final hasFlavorEnv = flavorEnv.existsSync();
    if (!hasFlavorEnv) {
      logger.warn(
        'No flavor-specific .env file found for flavor: $flavor (expected path: ${flavorEnv.path})',
      );
    }

    return (file: flavorEnv, exists: hasFlavorEnv);
  }

  /// Raw `KEY=VALUE` strings passed via repeated `--dart-define` flags.
  ///
  /// Must be space-separated (`--dart-define KEY=VALUE`), not `=`-joined
  /// (`--dart-define=KEY=VALUE`) — [Args.parse] splits on every `=` in an
  /// arg, so a joined value containing its own `=` fails to parse.
  List<String> get _cliDefines {
    return switch (args.values['dart-define']) {
      null => const [],
      final Iterable<dynamic> defines => [for (final d in defines) '$d'],
      final define => ['$define'],
    };
  }

  Map<String, String> get items {
    if (_items case final items? when kIsCompiled) {
      return Map.unmodifiable(items);
    }

    final (file: env, :exists) = this.env;
    final cliDefines = _cliDefines;

    if (!exists && cliDefines.isEmpty) {
      return {};
    }

    final items = <String, String>{};

    void addEntry(String raw) {
      final firstEqual = raw.indexOf('=');
      if (firstEqual == -1) return;

      final key = raw.substring(0, firstEqual);
      final value = raw.substring(firstEqual + 1);

      if (key.isEmpty) return;

      items[key] = parseEnvValue(value);
    }

    if (exists) {
      for (final line in env.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        addEntry(trimmed);
      }
    }

    // CLI-supplied defines override matching keys from the .env file.
    cliDefines.forEach(addEntry);

    return _items = Map.unmodifiable(items);
  }
}
