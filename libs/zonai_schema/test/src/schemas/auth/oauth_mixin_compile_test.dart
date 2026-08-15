// Proves the developer-experience invariant from oauth-schema-types: `with
// OAuth` without overriding `oauthProviders` must not compile, exactly like
// `with PasswordAuth` without overriding `passwordHash` doesn't. That's a
// property of the abstract getter, checked here by literally handing both
// shapes to the analyzer (same idiom as apps/playground's
// doc_snippets_test.dart) rather than asserted about and hoped for.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _fixtureHeader = '''
import 'package:zonai_schema/zonai_schema.dart';

class _FixtureId implements Id {
  const _FixtureId(this.value);
  @override
  final String value;
}

class _FixtureUser {
  const _FixtureUser({
    required this.id,
    required this.email,
    required this.isVerified,
  });
  final _FixtureId id;
  final String email;
  final bool isVerified;
}
''';

String _table({required bool withOverride}) => '''
$_fixtureHeader
final class _FixtureUserTable extends AuthTable<_FixtureUser> with OAuth {
  _FixtureUserTable(super.\$)
    : id = \$.id(
        'id',
        (s) => s.id,
        fromString: _FixtureId.new,
        generate: () => const _FixtureId('g'),
      ),
      email = \$.email('email', (s) => s.email),
      isVerified = \$.isVerified('is_verified', (s) => s.isVerified);

  @override
  _FixtureUser fromRow(RowReader read) => _FixtureUser(
    id: read(id),
    email: read(email),
    isVerified: read(isVerified),
  );

  @override
  final IdColumn<_FixtureId> id;
  @override
  final EmailColumn email;
  @override
  final IsVerifiedColumn isVerified;
  ${withOverride ? '''
  @override
  List<OAuthProvider> get oauthProviders => const [];
''' : '// oauthProviders intentionally left unoverridden.'}
}
''';

void main() {
  test(
    'with OAuth without overriding oauthProviders fails to analyze, and '
    'with the override present it analyzes clean',
    () async {
      final packageRoot = Directory.current.path;
      final dir = Directory(
        p.join(packageRoot, 'test', 'src', 'schemas', 'auth', '__oauth_mixin_scratch__'),
      );
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);

      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      File(
        p.join(dir.path, 'missing_override.dart'),
      ).writeAsStringSync(_table(withOverride: false));
      File(
        p.join(dir.path, 'with_override.dart'),
      ).writeAsStringSync(_table(withOverride: true));

      final result = await Process.run('dart', [
        'analyze',
        '--format',
        'machine',
        dir.path,
      ], workingDirectory: packageRoot);

      final errorsByFile = <String, List<String>>{};
      for (final line in const LineSplitter().convert(
        result.stdout as String,
      )) {
        final parts = line.split('|');
        if (parts.length < 8 || parts[0] != 'ERROR') continue;
        final file = p.basename(parts[3]);
        (errorsByFile[file] ??= []).add(parts[7]);
      }

      expect(
        errorsByFile['missing_override.dart'],
        isNotNull,
        reason:
            'with OAuth without overriding oauthProviders must be a '
            'compile error (missing concrete implementation), but the '
            'analyzer reported none. Full stdout:\n${result.stdout}',
      );
      expect(
        errorsByFile['missing_override.dart']!.any(
          (msg) => msg.contains('oauthProviders'),
        ),
        isTrue,
        reason:
            'expected an error mentioning oauthProviders, got: '
            '${errorsByFile['missing_override.dart']}',
      );

      expect(
        errorsByFile['with_override.dart'],
        isNull,
        reason:
            'overriding oauthProviders should analyze clean, but got: '
            '${errorsByFile['with_override.dart']}',
      );
    },
  );
}
