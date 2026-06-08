import 'dart:io';
import 'package:resqlite/resqlite.dart';

Future<void> main() async {
  final lib = File('lib/gen/native/libresqlite.dylib');
  install(lib.absolute.path);
  final dir = await Directory.systemTemp.createTemp('min_');
  final db = await Database.open('${dir.path}/t.sqlite');
  print('opened OK');
  await db.close();
}
