/// Parses a human-written size like `512mb`, `1gb`, `256 KB` or a bare byte
/// count into bytes.
///
/// Returns `null` when [input] is not a positive integer optionally followed
/// by a single unit suffix, so callers can report the offending value
/// themselves rather than guessing at an intent.
///
/// Units are powers of 1024, matching what `df`, SQLite page arithmetic and
/// every operator staring at a full volume already mean by "MB". A bare
/// number is bytes.
///
/// Zero is rejected along with negatives: a zero-byte ceiling is never what
/// someone meant, and silently accepting it would stop a database from
/// accepting a single row.
int? parseBytes(String input) {
  final match = RegExp(
    r'^(\d+)\s*(b|kb|mb|gb|tb)?$',
    caseSensitive: false,
  ).firstMatch(input.trim());

  if (match == null) return null;

  final amount = int.tryParse(match.group(1)!);
  if (amount == null || amount <= 0) return null;

  final multiplier = switch (match.group(2)?.toLowerCase()) {
    null || 'b' => 1,
    'kb' => 1024,
    'mb' => 1024 * 1024,
    'gb' => 1024 * 1024 * 1024,
    'tb' => 1024 * 1024 * 1024 * 1024,
    _ => null,
  };
  if (multiplier == null) return null;

  return amount * multiplier;
}
