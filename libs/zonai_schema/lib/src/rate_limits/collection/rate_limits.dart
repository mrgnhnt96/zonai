library rate_limits;

import 'dart:async';

import 'package:raindrop/raindrop.dart';
import 'package:zonai_schema/zonai_schema.dart';

part 'auth_collection_rate_limits.dart';
part 'collection_rate_limits.dart';

sealed class RateLimits<S extends Schema<R>, R> {
  const RateLimits(this.schema);

  final S schema;

  Table<S, R> get table => Table.getFor(schema);
}
