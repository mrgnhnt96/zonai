import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/db/token/create.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

/// Every refusal `zonai db token create` can make **before** it touches the
/// database.
///
/// The scope below registers only `args` and `logger`, exactly like
/// `help_test.dart`: a check that slipped past its guard and reached the
/// database would fail here by throwing on an unregistered provider, not by
/// quietly minting a credential in whatever directory the test happened to
/// run in.
///
/// Worth its own file because these are the messages someone reads at the
/// moment they are trying to issue a credential, and a bad one here is
/// answered by guessing at a scope.
class _CapturingSink implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}

Future<({int exitCode, String output})> _create(
  Map<String, dynamic> options,
) async {
  final sink = _CapturingSink();
  final exitCode = await runScoped(
    createToken,
    values: {
      argsProvider.overrideWith(() => Args(args: options)),
      loggerProvider.overrideWith(
        () => Logger(level: .info, stdout: IOSink(sink), stderr: IOSink(sink)),
      ),
    },
  );
  return (exitCode: exitCode, output: sink.text);
}

void main() {
  group('refused before anything is minted', () {
    test('no name', () async {
      final result = await _create({'tables': 'orders', 'read': true});

      expect(result.exitCode, 1);
      expect(result.output, contains('--name'));
    });

    test('a blank name', () async {
      // An unnamed credential is one nobody ever revokes, because nobody can
      // tell what would break.
      final result = await _create({
        'name': '   ',
        'tables': 'orders',
        'read': true,
      });

      expect(result.exitCode, 1);
      expect(result.output, contains('--name'));
    });

    test('no tables', () async {
      final result = await _create({'name': 'backup', 'read': true});

      expect(result.exitCode, 1);
      expect(result.output, contains('--tables'));
    });

    test('no operations, and neither shorthand', () async {
      final result = await _create({'name': 'backup', 'tables': 'orders'});

      expect(result.exitCode, 1);
      expect(result.output, contains('--operations'));
      expect(result.output, contains('can do nothing'));
    });

    test('an operation that does not exist', () async {
      final result = await _create({
        'name': 'backup',
        'tables': 'orders',
        'operations': 'list,teleport',
      });

      expect(result.exitCode, 1);
      expect(result.output, contains('teleport'));
      // Naming the real ones, rather than only rejecting the typo.
      expect(result.output, contains('delete'));
    });

    test('--can-edit alongside --no-admin', () async {
      // A token is an admin unless --no-admin says otherwise, so the pair
      // that cannot be meant is now this one rather than a bare --can-edit.
      // `--can-edit` on its own is no longer refused at all -- it falls
      // through to the mint, which is past this file's boundary; the scope's
      // own tests carry that half.
      final result = await _create({
        'name': 'backup',
        'tables': 'orders',
        'write': true,
        'admin': false,
        'can-edit': true,
      });

      expect(result.exitCode, 1);
      expect(result.output, contains('--no-admin'));
    });

    test('an --expires that is not a duration', () async {
      final result = await _create({
        'name': 'backup',
        'tables': 'orders',
        'read': true,
        'expires': 'soon',
      });

      expect(result.exitCode, 1);
      expect(result.output, contains('90d'));
    });

    test('--claims that is not JSON', () async {
      final result = await _create({
        'name': 'backup',
        'tables': 'orders',
        'read': true,
        'claims': 'role=reporting',
      });

      expect(result.exitCode, 1);
      expect(result.output, contains('--claims'));
    });

    test('an --as that is not table/id', () async {
      final result = await _create({
        'name': 'backup',
        'tables': 'orders',
        'read': true,
        'as': 'users',
      });

      expect(result.exitCode, 1);
      expect(result.output, contains('<table>/<row-id>'));
    });
  });

  group('--operations "*"', () {
    test('satisfies the "name at least one operation" refusal', () async {
      // It cannot mint here -- this scope registers no database -- so the
      // proof that the wildcard was accepted is that the run got PAST
      // validation and failed on the database instead.
      final result = await _create({
        'name': 'backup',
        'tables': 'orders',
        'operations': '*',
      });

      expect(result.output, isNot(contains('Missing required option')));
      expect(result.output, contains('Failed to create API token'));
    });

    test('an unknown name is still refused, and now points at "*"', () async {
      final result = await _create({
        'name': 'backup',
        'tables': 'orders',
        'operations': 'list,teleport',
      });

      expect(result.exitCode, 1);
      expect(result.output, contains('teleport'));
      expect(result.output, contains('"*"'));
    });
  });
}
