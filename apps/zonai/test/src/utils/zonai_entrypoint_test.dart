import 'dart:io';

import 'package:test/test.dart';
import 'package:zonai/src/utils/zonai_entrypoint.dart';

void main() {
  test('zonaiSourceEntrypoint resolves bin/zonai.dart', () {
    final entry = zonaiSourceEntrypoint();
    expect(entry, isNotNull);
    expect(File(entry!).existsSync(), isTrue);
    expect(
      entry.endsWith(
        '${Platform.pathSeparator}bin${Platform.pathSeparator}zonai.dart',
      ),
      isTrue,
    );
  });
}
