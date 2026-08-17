/// The shared runtime every generated table file imports.
///
/// Written once and emitted verbatim rather than generated per table: these
/// helpers are the layer §8.2 identifies as the one that actually protects a
/// shipped app, because they work regardless of version skew and need no
/// server cooperation. A per-table copy would be a per-table opportunity to
/// diverge.
///
/// Raw string so the Dart below can use `$` without escaping; the file header
/// is prepended by the emitter.
library;

const kClientRuntimeSource = r'''
import 'dart:convert';

/// Thrown when a row does not have the shape this client was generated from.
///
/// The point of this type is the four things it names. A bare `TypeError` out
/// of a `fromJson` says "type 'String' is not a subtype of type 'int'" and
/// leaves the reader to work out which of forty columns it meant; this says
/// which table, which column, what was expected and what actually arrived.
///
/// It is also the only drift protection that survives version skew. A shipped
/// mobile app cannot be force-updated, so the client never refuses to talk to
/// a server whose schema moved -- it keeps working for every column it still
/// understands and reports precisely on the one it does not.
final class ZonaiRowParseException implements Exception {
  const ZonaiRowParseException({
    required this.table,
    required this.column,
    required this.expected,
    required this.actual,
  });

  /// The table the row came from.
  final String table;

  /// The column that did not parse.
  final String column;

  /// The column kind expected, with the wire shape it arrives in --
  /// `createdAt (epoch-millisecond int)`.
  final String expected;

  /// The runtime type the row actually carried. `Null` when the column was
  /// missing or null where the schema says it cannot be.
  final Type actual;

  @override
  String toString() =>
      'ZonaiRowParseException: $table.$column expected $expected, but the row '
      'carried $actual. The server schema has probably moved since this '
      'client was generated -- re-run `zonai gen client`.';
}

/// Decodes one table's raw rows.
///
/// Rows arrive as **raw SQLite storage values**: the server returns
/// `result.rows.map((e) => e.toMap())` and only strips secret columns and
/// resolves photo URLs on the way out. Nothing runs the column transformers.
/// So a `dateTime` is an epoch-millisecond `int`, a `boolean` is `0` or `1`,
/// and `list` / `map` / `enumList` are JSON-encoded strings.
///
/// Every method here throws [ZonaiRowParseException] rather than letting a
/// `TypeError` escape. That is the whole contract: a `TypeError` out of any of
/// these is a bug.
final class ZonaiRowReader {
  const ZonaiRowReader(this.table);

  /// The table these rows came from, so failures can name it.
  final String table;

  Never _fail(String column, String kind, String wire, Object? value) {
    throw ZonaiRowParseException(
      table: table,
      column: column,
      expected: '$kind ($wire)',
      actual: value.runtimeType,
    );
  }

  Object _require(Map<String, Object?> json, String column, String kind,
      String wire) {
    final value = json[column];
    if (value == null) _fail(column, kind, wire, value);
    return value;
  }

  static const _wireString = 'String';
  static const _wireInt = 'int';
  static const _wireNum = 'int or double';
  static const _wireBool = 'int 0/1';
  static const _wireMs = 'epoch-millisecond int';
  static const _wireBytes = 'byte list';
  static const _wireUrl = 'resolved URL String';
  static const _wireUrls = 'list of resolved URL Strings';
  static const _wireJsonList = 'JSON-encoded list String';
  static const _wireJsonMap = 'JSON-encoded object String';

  String string(Map<String, Object?> json, String column,
          {required String kind}) =>
      switch (_require(json, column, kind, _wireString)) {
        final String value => value,
        final other => _fail(column, kind, _wireString, other),
      };

  String? stringOrNull(Map<String, Object?> json, String column,
          {required String kind}) =>
      switch (json[column]) {
        null => null,
        final String value => value,
        final other => _fail(column, kind, _wireString, other),
      };

  int integer(Map<String, Object?> json, String column,
          {required String kind}) =>
      switch (_require(json, column, kind, _wireInt)) {
        final int value => value,
        final other => _fail(column, kind, _wireInt, other),
      };

  int? integerOrNull(Map<String, Object?> json, String column,
          {required String kind}) =>
      switch (json[column]) {
        null => null,
        final int value => value,
        final other => _fail(column, kind, _wireInt, other),
      };

  /// A REAL column. Accepts `int` too: SQLite hands back an integer for a
  /// whole-numbered REAL, and JSON does not distinguish `1` from `1.0`.
  double real(Map<String, Object?> json, String column,
          {required String kind}) =>
      switch (_require(json, column, kind, _wireNum)) {
        final num value => value.toDouble(),
        final other => _fail(column, kind, _wireNum, other),
      };

  double? realOrNull(Map<String, Object?> json, String column,
          {required String kind}) =>
      switch (json[column]) {
        null => null,
        final num value => value.toDouble(),
        final other => _fail(column, kind, _wireNum, other),
      };

  /// `BooleanTransformer` stores `0` / `1`; `bool` is accepted as well so a
  /// row that has already been through a decoding layer still parses.
  bool boolean(Map<String, Object?> json, String column,
          {required String kind}) =>
      switch (_require(json, column, kind, _wireBool)) {
        final bool value => value,
        final int value => value != 0,
        final other => _fail(column, kind, _wireBool, other),
      };

  bool? booleanOrNull(Map<String, Object?> json, String column,
          {required String kind}) =>
      switch (json[column]) {
        null => null,
        final bool value => value,
        final int value => value != 0,
        final other => _fail(column, kind, _wireBool, other),
      };

  /// `DateTimeTransformer` encodes to `millisecondsSinceEpoch`.
  DateTime dateTime(Map<String, Object?> json, String column,
          {required String kind}) =>
      switch (_require(json, column, kind, _wireMs)) {
        final int value => DateTime.fromMillisecondsSinceEpoch(value),
        final other => _fail(column, kind, _wireMs, other),
      };

  DateTime? dateTimeOrNull(Map<String, Object?> json, String column,
          {required String kind}) =>
      switch (json[column]) {
        null => null,
        final int value => DateTime.fromMillisecondsSinceEpoch(value),
        final other => _fail(column, kind, _wireMs, other),
      };

  /// `BigIntTransformer` stores one sign byte then big-endian magnitude, in a
  /// BLOB -- which reaches a client as a list of ints once it has been through
  /// JSON. A bare `int` is accepted for the same reason the server accepts one.
  BigInt bigInt(Map<String, Object?> json, String column,
          {required String kind}) =>
      _bigIntFrom(_require(json, column, kind, _wireBytes), column, kind);

  BigInt? bigIntOrNull(Map<String, Object?> json, String column,
          {required String kind}) {
    final value = json[column];
    if (value == null) return null;
    return _bigIntFrom(value, column, kind);
  }

  BigInt _bigIntFrom(Object value, String column, String kind) {
    if (value is int) return BigInt.from(value);
    if (value is! List) _fail(column, kind, _wireBytes, value);

    final bytes = <int>[];
    for (final byte in value) {
      if (byte is! int) _fail(column, kind, _wireBytes, value);
      bytes.add(byte);
    }
    if (bytes.isEmpty) return BigInt.zero;

    var magnitude = BigInt.zero;
    for (final byte in bytes.skip(1)) {
      magnitude = (magnitude << 8) | BigInt.from(byte);
    }
    return bytes.first == 1 ? -magnitude : magnitude;
  }

  List<int> bytes(Map<String, Object?> json, String column,
          {required String kind}) =>
      _bytesFrom(_require(json, column, kind, _wireBytes), column, kind);

  List<int>? bytesOrNull(Map<String, Object?> json, String column,
      {required String kind}) {
    final value = json[column];
    if (value == null) return null;
    return _bytesFrom(value, column, kind);
  }

  List<int> _bytesFrom(Object value, String column, String kind) {
    if (value is! List) _fail(column, kind, _wireBytes, value);
    return [
      for (final byte in value)
        if (byte is int) byte else _fail(column, kind, _wireBytes, value),
    ];
  }

  /// A photo column. `_resolvePhotoFields` has already rewritten the stored id
  /// into a fully-qualified URL by the time a row reaches here.
  Uri uri(Map<String, Object?> json, String column, {required String kind}) =>
      _uriFrom(_require(json, column, kind, _wireUrl), column, kind);

  Uri? uriOrNull(Map<String, Object?> json, String column,
      {required String kind}) {
    final value = json[column];
    if (value == null) return null;
    return _uriFrom(value, column, kind);
  }

  Uri _uriFrom(Object value, String column, String kind) {
    if (value is! String) _fail(column, kind, _wireUrl, value);
    final parsed = Uri.tryParse(value);
    if (parsed == null) _fail(column, kind, _wireUrl, value);
    return parsed;
  }

  List<Uri> uriList(Map<String, Object?> json, String column,
          {required String kind}) =>
      _uriListFrom(_require(json, column, kind, _wireUrls), column, kind);

  List<Uri>? uriListOrNull(Map<String, Object?> json, String column,
      {required String kind}) {
    final value = json[column];
    if (value == null) return null;
    return _uriListFrom(value, column, kind);
  }

  List<Uri> _uriListFrom(Object value, String column, String kind) {
    final raw = value is String
        ? _decodeJson(value, column, kind, _wireUrls)
        : value;
    if (raw is! List) _fail(column, kind, _wireUrls, value);
    return [
      for (final item in raw)
        if (item == null)
          _fail(column, kind, _wireUrls, value)
        else
          _uriFrom(item, column, kind),
    ];
  }

  /// `enumList` -- a JSON-encoded array of enum names.
  List<String> stringList(Map<String, Object?> json, String column,
          {required String kind}) =>
      _stringListFrom(
          _require(json, column, kind, _wireJsonList), column, kind);

  List<String>? stringListOrNull(Map<String, Object?> json, String column,
      {required String kind}) {
    final value = json[column];
    if (value == null) return null;
    return _stringListFrom(value, column, kind);
  }

  List<String> _stringListFrom(Object value, String column, String kind) {
    final raw = _listFrom(value, column, kind);
    return [
      for (final item in raw)
        if (item is String)
          item
        else
          _fail(column, kind, _wireJsonList, value),
    ];
  }

  List<Object?> list(Map<String, Object?> json, String column,
          {required String kind}) =>
      _listFrom(_require(json, column, kind, _wireJsonList), column, kind);

  List<Object?>? listOrNull(Map<String, Object?> json, String column,
      {required String kind}) {
    final value = json[column];
    if (value == null) return null;
    return _listFrom(value, column, kind);
  }

  List<Object?> _listFrom(Object value, String column, String kind) {
    if (value is List) return value;
    if (value is! String) _fail(column, kind, _wireJsonList, value);
    if (value.isEmpty) return const [];

    final decoded = _decodeJson(value, column, kind, _wireJsonList);
    if (decoded is! List) _fail(column, kind, _wireJsonList, decoded);
    return decoded;
  }

  Map<String, Object?> map(Map<String, Object?> json, String column,
          {required String kind}) =>
      _mapFrom(_require(json, column, kind, _wireJsonMap), column, kind);

  Map<String, Object?>? mapOrNull(Map<String, Object?> json, String column,
      {required String kind}) {
    final value = json[column];
    if (value == null) return null;
    return _mapFrom(value, column, kind);
  }

  Map<String, Object?> _mapFrom(Object value, String column, String kind) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.cast<String, Object?>();
    if (value is! String) _fail(column, kind, _wireJsonMap, value);
    if (value.isEmpty) return const {};

    final decoded = _decodeJson(value, column, kind, _wireJsonMap);
    if (decoded is! Map) _fail(column, kind, _wireJsonMap, decoded);
    return decoded.cast<String, Object?>();
  }

  /// A malformed JSON payload is drift like any other, so it reports the same
  /// way rather than as a bare `FormatException` from `dart:convert`.
  Object? _decodeJson(String value, String column, String kind, String wire) {
    try {
      return jsonDecode(value);
    } on FormatException {
      _fail(column, kind, wire, value);
    }
  }

  /// A nested row object: the `expanded` key itself, or one related row inside
  /// it keyed by its foreign-key column name.
  ///
  /// Absent rather than empty when nothing was expanded, which is why this
  /// returns null instead of throwing -- an unexpanded row is not drift.
  static Map<String, Object?>? nested(Object? value) => switch (value) {
        final Map<String, Object?> map => map,
        final Map<Object?, Object?> map => map.cast<String, Object?>(),
        _ => null,
      };
}

/// The `Authorization` header value, in a form that cannot be built wrong.
///
/// The server's `_parseBearerAuthorization` requires the `Bearer ` prefix and
/// **returns null when it is missing rather than throwing**, so a bare JWT does
/// not produce an auth error -- the request proceeds as *unauthenticated*, and
/// the table's rules decide what happens next: a 403 that reads like a
/// permissions bug, or a successful public read that quietly returns fewer rows
/// than the caller expected. A silent demotion is strictly worse than a
/// rejection, and it is invisible at the call site.
///
/// [Authorization.bearer] makes that unrepresentable. Being an extension type
/// over `String`, it erases at runtime, so the wire is exactly what it was.
///
/// Omit it and the call falls through to the ambient token the client's
/// interceptor already sets -- `client.posts.list()` is authenticated exactly
/// as `client.db.list(...)` is today.
extension type const Authorization._(String header) {
  /// Wraps a bare access token with the `Bearer ` prefix the server requires.
  factory Authorization.bearer(String token) => Authorization._('Bearer $token');

  /// Escape hatch for a header value that is already complete.
  const Authorization.raw(String header) : this._(header);
}
''';
