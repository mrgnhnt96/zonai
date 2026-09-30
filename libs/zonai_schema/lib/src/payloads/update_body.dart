import 'package:revali_core/revali_core.dart' show HttpError;

import '../types/where.dart';
import '../update/update.dart';

class UpdateBody {
  const UpdateBody({
    required this.table,
    required this.where,
    this.limit,
    required this.updates,
    this.expect,
  });

  final String table;
  final Where where;
  final int? limit;
  final List<Update> updates;

  /// A precondition every target row must meet. When any does not, the server
  /// writes nothing and answers `412` with code `precondition_failed`, carrying
  /// the failing rows as `details.current` -- so "the row changed under you"
  /// is distinguishable from "the row is gone" (`404`).
  ///
  /// Typical use is optimistic concurrency: `expect: Eq('rev', 3)`.
  ///
  /// A server that predates this field ignores it and applies the update
  /// unconditionally, so a client that depends on it must know its server.
  final Where? expect;

  factory UpdateBody.fromJson(Map<String, dynamic> json) {
    return UpdateBody(
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      limit: json['limit'] as int?,
      updates: [
        for (final update in json['updates'] as List<dynamic>)
          Update.fromJson(update as Map<String, dynamic>),
      ],
      expect: _expectFromJson(json['expect']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'table': table,
      'where': where.toJson(),
      'limit': ?limit,
      'updates': [for (final update in updates) update.toJson()],
      if (expect case final expect?) 'expect': expect.toJson(),
    };
  }
}

/// Only a missing key or JSON `null` means "no precondition". Anything else
/// that is not a where-object is refused: reading `[]` or `"rev=3"` as absent
/// would turn a conditional write into an unconditional one -- the lost update
/// `expect` exists to prevent (review of #50).
Where? _expectFromJson(Object? json) => switch (json) {
  null => null,
  final Map<dynamic, dynamic> json => Where.fromJson(json),
  // A 400 the caller can branch on. An ArgumentError here surfaced as a 500:
  // nothing maps a body-parse ArgumentError to a status.
  final value => throw HttpError.badRequest(
    code: 'invalid_expect',
    message:
        '`expect` must be a where object, or null/absent for no '
        'precondition; got ${value.runtimeType}',
  ),
};

class UpdateOneBody extends UpdateBody {
  const UpdateOneBody({
    required super.table,
    required super.where,
    required super.updates,
    super.expect,
  }) : super(limit: 1);

  factory UpdateOneBody.fromJson(Map<String, dynamic> json) {
    return UpdateOneBody(
      table: json['table'] as String,
      where: Where.fromJson(json['where'] as Map<String, dynamic>),
      updates: [
        for (final update in json['updates'] as List<dynamic>)
          Update.fromJson(update as Map<String, dynamic>),
      ],
      expect: _expectFromJson(json['expect']),
    );
  }
}
