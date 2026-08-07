import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';
import 'package:zonai/src/commands/db/admin/list.dart';
import 'package:zonai/src/deps/args.dart';
import 'package:zonai/src/deps/logger.dart';
import 'package:zonai/src/deps/settings.dart';
import 'package:zonai/src/deps/zonai_db.dart';
import 'package:zonai/src/utils/args.dart';
import 'package:zonai_logger/zonai_logger.dart';

import 'fake_zonai_db.dart';

class _CapturingSink implements StreamConsumer<List<int>> {
  final bytes = <int>[];

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.forEach(bytes.addAll);
  }

  @override
  Future<void> close() async {}

  String get text => utf8.decode(bytes);
}

Future<int> _run(Args args, {FakeZonaiDb? db, IOSink? stdout}) {
  final fakeDb = db ?? newFakeZonaiDb();
  return runScoped(
    listAdmins,
    values: {
      argsProvider.overrideWith(() => args),
      loggerProvider.overrideWith(
        () => Logger(level: .info, stdout: stdout, stderr: stdout),
      ),
      settingsProvider.overrideWith(() => fakeSettings),
      zonaiDbProvider.overrideWith(() => () => fakeDb),
    },
  );
}

void main() {
  group('listAdmins', () {
    test('succeeds with no admins', () async {
      final exitCode = await _run(Args(args: {}));
      expect(exitCode, 0);
    });

    test('calls ZonaiDb.listAdmins and succeeds', () async {
      final db = newFakeZonaiDb()
        ..listAdminsResult = [
          {'id': 'a1', 'email': 'a@example.com', 'is_verified': true},
          {'id': 'a2', 'email': 'b@example.com', 'is_verified': false},
        ];

      final exitCode = await _run(Args(args: {}), db: db);

      expect(exitCode, 0);
      expect(db.listAdminsCalled, isTrue);
    });

    test('never prints a password field even if one is present', () async {
      final db = newFakeZonaiDb()
        ..listAdminsResult = [
          {
            'id': 'a1',
            'email': 'a@example.com',
            'password': 'super-secret-hash',
          },
        ];
      final sink = _CapturingSink();

      final exitCode = await _run(
        Args(args: {}),
        db: db,
        stdout: IOSink(sink),
      );

      expect(exitCode, 0);
      expect(sink.text, contains('a@example.com'));
      expect(sink.text, isNot(contains('super-secret-hash')));
    });

    test('fails when the underlying list throws', () async {
      final db = newFakeZonaiDb()
        ..listAdminsError = StateError('boom');

      final exitCode = await _run(Args(args: {}), db: db);

      expect(exitCode, 1);
    });
  });
}
