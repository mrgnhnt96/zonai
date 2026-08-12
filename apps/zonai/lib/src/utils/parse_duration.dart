/// Parses a human-written age like `7d`, `24h`, `30m`, `90s` or `2w` into a
/// [Duration].
///
/// Returns `null` when [input] is not a non-negative integer followed by a
/// single unit suffix, so callers can report the offending value themselves
/// rather than guessing at an intent.
///
/// Months and years are deliberately unsupported: neither has a fixed length,
/// so `1mo` would have to pick a meaning silently on the user's behalf.
Duration? parseDuration(String input) {
  final match = RegExp(
    r'^(\d+)\s*(s|m|h|d|w)$',
    caseSensitive: false,
  ).firstMatch(input.trim());

  if (match == null) return null;

  final amount = int.tryParse(match.group(1)!);
  if (amount == null) return null;

  return switch (match.group(2)!.toLowerCase()) {
    's' => Duration(seconds: amount),
    'm' => Duration(minutes: amount),
    'h' => Duration(hours: amount),
    'd' => Duration(days: amount),
    'w' => Duration(days: amount * 7),
    _ => null,
  };
}
