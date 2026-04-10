/// Severity for log lines. Higher values are more important.
///
/// A [Logger] is configured with a minimum [Level]; messages at that level or
/// higher are emitted.
enum Level { verbose, trace, debug, info, warning, error }
