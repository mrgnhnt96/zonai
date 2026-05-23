import 'package:zonai/src/deps/args.dart';

/// Whether zonai is compiled and is in use by a developer
const kIsCompiled = bool.fromEnvironment('__ZONAI_COMPILED__');

/// Whether zonai is running in release mode (running on a server, not in development)
///
/// Enable by passing `--release` to the zonai `serve` command.
bool get kReleaseMode => args.getOrNull<bool>('release') ?? false;
