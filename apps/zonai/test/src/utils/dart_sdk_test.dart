import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:zonai/src/utils/dart_sdk.dart';

void main() {
  group('dartSdkVersion', () {
    // The one test that proves the parse against a real SDK rather than
    // restating the shape of a string this file also wrote. The suite runs on
    // the VM, so `resolvedExecutable` is a genuine `dart`.
    final resolved = io.Platform.resolvedExecutable;

    test('reads the bare version out of a real SDK', () async {
      final version = await dartSdkVersion(resolved);

      expect(version, isNotNull);
      expect(version, matches(RegExp(r'^\d+\.\d+\.\d+')));
      // Not the whole line: no build date, no platform, no parentheses.
      expect(version, isNot(contains(' ')));
    });

    test('agrees with what the executable actually printed', () async {
      final version = await dartSdkVersion(resolved);
      final printed = await io.Process.run(resolved, ['--version']);
      final output = '${printed.stdout}${printed.stderr}';

      expect(version, isNotNull);
      expect(output, contains('Dart SDK version: $version '));
    });

    // A null here has to mean UNKNOWN, not a thrown exception: this runs
    // straight after a compile that already succeeded, and a throw would lose
    // the artifact the stamp is describing.
    test('returns null instead of throwing when there is no such SDK', () {
      expect(
        dartSdkVersion(p.join('/no', 'such', 'sdk', 'bin', 'dart')),
        completion(isNull),
      );
    });

    // Exits 0 and prints something, just not a version line. Distinct from the
    // case above, which never gets as far as reading output.
    final echo = io.File('/bin/echo');
    test(
      'returns null for an executable that says nothing about a version',
      () async {
        expect(await dartSdkVersion(echo.path), isNull);
      },
      skip: echo.existsSync() ? null : 'no /bin/echo on this platform',
    );
  });
}
