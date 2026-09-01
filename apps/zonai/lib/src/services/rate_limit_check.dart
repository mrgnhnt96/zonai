import 'package:zonai_schema/zonai_schema.dart';

/// What `RateLimiter.check` found out about one request against one bucket.
///
/// Carries everything a 429 needs to be actionable (GitHub issue #32): the
/// policy's ceiling, how much of it is left, and the instant the window
/// resets. Computed inside the limiter's transaction from the row it read or
/// wrote, so the numbers describe the same window the verdict does.
///
/// The window is FIXED, not sliding: it starts at the first counted request,
/// and [resetAt] is `window_start + window`. A refused request neither
/// increments the counter nor moves the window, so [resetAt] is stable across
/// a burst of refusals -- which is what lets a client wait once instead of
/// polling.
final class RateLimitCheck {
  const RateLimitCheck({
    required this.allowed,
    required this.table,
    required this.operation,
    required this.limit,
    required this.remaining,
    required this.resetAt,
    this.customOperation,
  });

  /// No policy applies to this bucket, so the request always passes and
  /// there is no window to describe.
  const RateLimitCheck.unlimited({
    required this.table,
    required this.operation,
    this.customOperation,
  }) : allowed = true,
       limit = null,
       remaining = null,
       resetAt = null;

  /// Whether the request may proceed.
  final bool allowed;

  /// The real collection (or synthetic bucket such as `__auth_confirm__`),
  /// never the internal `table:customOperation` storage key.
  final String table;

  final RateLimitOperation operation;

  /// The registered custom operation name, when [operation] is
  /// [RateLimitOperation.custom] and the name was validated. `null` for
  /// every other operation, and for the coarse per-table custom bucket.
  final String? customOperation;

  /// The policy's `maxRequests`. `null` when unlimited.
  final int? limit;

  /// Requests left in the current window after this one, never negative.
  /// `null` when unlimited.
  final int? remaining;

  /// The instant the current window resets (`window_start + window`), in
  /// UTC. `null` when unlimited.
  final DateTime? resetAt;

  /// Whether no policy applies. When true every other number is `null`.
  bool get isUnlimited => limit == null;
}
