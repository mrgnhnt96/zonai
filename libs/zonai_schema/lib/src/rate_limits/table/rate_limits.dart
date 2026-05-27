library rate_limits;

import 'dart:async';

import 'package:raindrop/raindrop.dart' as rd;
import 'package:zonai_schema/zonai_schema.dart';

part 'auth_table_rate_limits.dart';
part 'table_rate_limits.dart';

sealed class RateLimits<S extends rd.Schema<R>, R> {
  const RateLimits(this.schema);

  final S schema;

  rd.Table<S, R> get table => rd.Table.getFor(schema);
}
