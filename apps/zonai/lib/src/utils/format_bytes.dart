/// Moved to `zonai_schema` so the admin web app can render the same sizes the
/// engine logs, without reaching into this package's `src/` or growing a
/// second implementation that rounds differently.
///
/// Re-exported from here rather than updated at each call site: the engine's
/// existing imports are the reason this file still exists.
export 'package:zonai_schema/src/utils/format_bytes.dart';
