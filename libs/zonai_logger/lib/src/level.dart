/// Severity for log lines. Higher values are more important.
///
/// A [Logger] is configured with a minimum [Level]; messages at that level or
/// higher are emitted.
enum Level {
  verbose,
  trace,
  debug,
  info,
  warning,
  error;

  const Level();

  static Level? fromString(String? level) {
    return switch (level) {
      'verbose' || 'v' => verbose,
      'trace' || 't' => trace,
      'debug' || 'd' => debug,
      'info' || 'i' => info,
      'warning' || 'w' => warning,
      'error' || 'e' => error,
      _ => null,
    };
  }

  bool operator <=(Level other) => index <= other.index;
  bool operator <(Level other) => index < other.index;

  bool operator >=(Level other) => index >= other.index;
  bool operator >(Level other) => index > other.index;
}
