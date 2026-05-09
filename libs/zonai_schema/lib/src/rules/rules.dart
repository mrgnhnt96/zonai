library rules;

import 'dart:async';

import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/zonai_schema.dart';

part 'collection/auth_collection_rules.dart';
part 'collection/base_collection_rules.dart';
part 'collection/collection_rules.dart';
part 'record/auth_record_rules.dart';
part 'record/base_record_rules.dart';
part 'record/record_rules.dart';

sealed class Rules<T extends Schema<T>> {
  const Rules(this.schema);

  final T schema;

  Table<T> get table => Table.getFor(schema);
}
