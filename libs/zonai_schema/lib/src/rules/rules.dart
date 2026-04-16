import 'dart:async';

import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/src/request.dart';
import 'package:zonai_schema/zonai_schema.dart';

part 'collection_rules.dart';
part 'record_rules.dart';

sealed class Rules<T extends Schema<T>> {
  Rules(this.schema);

  final T schema;

  Table<T> get table => Table.getFor(schema);
}
