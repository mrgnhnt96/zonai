import 'dart:convert';

import 'package:revali_router/revali_router.dart';
import 'package:zonai_schema/payloads.dart';

/// Decodes a `?body=<json>` query parameter exactly as the client sent it.
///
/// A plain `@Query() GetBody body` would read revali's coerced query map, and
/// revali coerces every string *inside* the decoded JSON as well: `'42'`
/// becomes `42`, `'true'` becomes `true`, and an all-digit string past int64
/// (`'21102800905892610131829'`) becomes a `double`. Bound against a TEXT
/// column that double is compared as `'2.11028009058926e+22'` and an `eq`
/// lookup finds nothing.
///
/// The pipe's `String` input is what makes revali hand over the raw query
/// value (`context.request.uri.queryParameters`) instead of the coerced one.
abstract base class QueryBodyPipe<T> implements Pipe<String, T> {
  const QueryBodyPipe();

  T fromJson(Map<String, dynamic> json);

  @override
  Future<T> transform(String value, PipeContext context) async {
    // Same 400 the generated `@Query()` binding answers for a missing, empty
    // or non-object body.
    MissingArgumentException missing(Object? actual) =>
        MissingArgumentException(
          key: context.nameOfParameter,
          location: '@query',
          expectedType: '$T',
          actualType: actual?.runtimeType.toString() ?? 'null',
        );

    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      throw missing(value);
    }

    return switch (decoded) {
      final Map<String, dynamic> data when data.isNotEmpty => fromJson(data),
      final mismatched => throw missing(mismatched),
    };
  }
}

final class GetBodyPipe extends QueryBodyPipe<GetBody> {
  const GetBodyPipe();

  @override
  GetBody fromJson(Map<String, dynamic> json) => GetBody.fromJson(json);
}

final class ListBodyPipe extends QueryBodyPipe<ListBody> {
  const ListBodyPipe();

  @override
  ListBody fromJson(Map<String, dynamic> json) => ListBody.fromJson(json);
}

final class CountBodyPipe extends QueryBodyPipe<CountBody> {
  const CountBodyPipe();

  @override
  CountBody fromJson(Map<String, dynamic> json) => CountBody.fromJson(json);
}
