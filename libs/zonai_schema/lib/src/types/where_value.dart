import 'dart:convert';

/// Normalizes [value] for JSON so wire format matches DB encodings (e.g. DateTime → ms).
Object? whereValueToJsonEncodable(Object? value) {
  return switch (value) {
    DateTime d => d.millisecondsSinceEpoch,
    final Map m => {
      for (final entry in m.entries)
        entry.key.toString(): whereValueToJsonEncodable(entry.value),
    },
    final List l => [for (final e in l) whereValueToJsonEncodable(e)],
    _ => value,
  };
}

Object serializeWhereValue(Object value) {
  return jsonDecode(jsonEncode(whereValueToJsonEncodable(value))) as Object;
}

/// The result must be a **plain** `List`, not a view.
///
/// `.cast<Object>()` returns a `CastList`, which is a regular instance rather
/// than one of the types an isolate message may contain. `Mailman` sends to an
/// isolate worker by handing the message graph straight to `SendPort.send`
/// (the process transport encodes it to bytes first, which is why this only
/// ever failed on one of the two), so a `CastList` anywhere inside it throws
/// `ArgumentError: ... is a regular instance reachable via ...` before the
/// request is ever dispatched.
///
/// This is the only [Where] serializer that builds a collection, so `In` and
/// `NotIn` were the only clauses affected — and they failed on every released
/// binary, since a release spawns the isolate transport.
List<Object> serializeWhereValues(List<Object> values) {
  return List<Object>.from(
    jsonDecode(jsonEncode(whereValueToJsonEncodable(values))) as List,
  );
}

/// Converts a [Where] comparison value to its bound-parameter form for the DB driver.
Object? whereValueToParam(Object value) {
  return switch (value) {
    DateTime d => d.millisecondsSinceEpoch,
    bool b => b ? 1 : 0,
    _ => value,
  };
}
