import 'dart:async';
import 'dart:io';

import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai/src/db_mutator/zonai_db/resqlite/resqlite_delegate.dart';
import 'package:resqlite/resqlite.dart' as rs;

Future<void> main() async {
  final lib = File('lib/gen/native/libresqlite.dylib');
  if (!lib.existsSync()) {
    stderr.writeln('Missing ${lib.path}');
    exit(1);
  }
  rs.install(lib.absolute.path);

  final dir = await Directory.systemTemp.createTemp('resqlite_repro_');
  final path = '${dir.path}/test.sqlite';

  final delegate = await ResqliteDelegate.open(path);
  final db = Raindrop(delegate);

  try {
    await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)');
    await db.execute("INSERT INTO t(name) VALUES ('a')");

    final rows = await db.execute('SELECT name FROM t WHERE name = ?', ['a']);
    stdout.writeln('read OK: ${rows.rows}');

    final stream = delegate.streamQuery('SELECT name FROM t ORDER BY id', const []);
    final emissions = <List<List<Object?>>>[];
    final done = Completer<void>();
    late final StreamSubscription<dynamic> sub;
    sub = stream.listen((result) {
      emissions.add(result.rows);
      if (emissions.length == 2) {
        unawaited(sub.cancel());
        done.complete();
      }
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    stdout.writeln('stream first: ${emissions.single}');

    await db.execute("INSERT INTO t(name) VALUES ('b')");
    await done.future;
    stdout.writeln('stream after insert: ${emissions.last}');

    stdout.writeln('ALL PASSED');
  } finally {
    await delegate.close();
    dir.deleteSync(recursive: true);
  }
}
