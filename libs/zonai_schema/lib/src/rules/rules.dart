library rules;

import 'dart:async';

import 'package:raindrop/raindrop.dart' as rd;
import 'package:zonai_schema/zonai_schema.dart';

part 'table/auth_table_rules.dart';
part 'table/base_table_rules.dart';
part 'table/table_rules.dart';
part 'record/auth_record_rules.dart';
part 'record/base_record_rules.dart';
part 'record/record_rules.dart';

sealed class Rules<S extends rd.Schema<R>, R> {
  const Rules(this.schema);

  final S schema;

  rd.Table<S, R> get table => rd.Table.getFor(schema);
}
