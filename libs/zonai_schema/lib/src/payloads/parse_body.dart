/// A request body that could not be read: a missing field, a wrong type, a
/// `where` that is not a where. The caller's mistake, so the server answers
/// `400 invalid_body`, not a `500` that reads as the server being broken.
///
/// An [ArgumentError], so code that already catches one when parsing a body
/// keeps working. It also implements [Exception]: revali hands only
/// `Exception`s to the server's exception catchers, and answers anything else
/// with a bare 500 before a catcher is asked.
final class InvalidBodyException extends ArgumentError implements Exception {
  InvalidBodyException(String super.message);

  @override
  String toString() => 'Invalid request body: $message';
}

/// Parses the request body [name] with [parse], turning any way a malformed
/// body can fail into an [InvalidBodyException].
///
/// Wrapped around a route body's whole `fromJson` rather than each field, so
/// the failures of nested types (`Where.fromJson`, `Update.fromJson`) and of
/// plain casts (`json['table'] as String`, which throws a [TypeError]) are
/// covered without each needing to know it is reading client input.
T parseBody<T>(String name, T Function() parse) {
  try {
    return parse();
  } on InvalidBodyException {
    rethrow;
  } on ArgumentError catch (e) {
    // `toString`, not `message`: it also carries the field's name and the
    // value that was refused, which is what tells the caller what to fix.
    throw InvalidBodyException('$name: $e');
  } on TypeError catch (e) {
    throw InvalidBodyException('$name: $e');
  } on FormatException catch (e) {
    throw InvalidBodyException('$name: ${e.message}');
  }
}
