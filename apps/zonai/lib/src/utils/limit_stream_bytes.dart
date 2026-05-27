/// Yields chunks from [source] until the cumulative size exceeds [maxBytes].
///
/// Throws [StateError] when the limit is exceeded.
Stream<List<int>> limitStreamBytes(Stream<List<int>> source, int maxBytes) async* {
  var total = 0;

  await for (final chunk in source) {
    total += chunk.length;
    if (total > maxBytes) {
      throw StateError(
        'Stream exceeds maximum size of $maxBytes bytes (received at least $total)',
      );
    }
    yield chunk;
  }
}
