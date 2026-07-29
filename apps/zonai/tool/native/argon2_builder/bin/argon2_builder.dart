// Never actually run -- this only needs to exist so `dart build cli`
// (invoked from the package root) has an entrypoint to build, which is
// what triggers sodium's build hook and produces the native library we
// embed. See tool/generate_argon2_native.dart.
import 'package:sodium/sodium_sumo.dart';

Future<void> main() async {
  await SodiumSumoInit.init();
}
