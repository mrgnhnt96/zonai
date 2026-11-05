import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart' as rd;
import 'package:zonai_schema/src/rate_limit/rate_limit_policy.dart';

/// A rate-limit counter for creates that is keyed on a value from the
/// submitted row instead of on the caller's IP address.
///
/// Returned from `TableRateLimits.createCounters`. Every create on the table
/// is counted against each counter (and against `createPolicy`'s per-IP
/// counter, unless that returns `null`), and is refused when any one of them
/// is spent. A refused create is not counted against any of them.
///
/// ```dart
/// @override
/// List<RateLimitCounter> createCounters() => [
///   RateLimitCounter(
///     name: 'app',
///     column: schema.apiKey,
///     // Only keys the table recognises get a counter of their own.
///     key: (apiKey) async => (await findApp(apiKey))?.id,
///     policy: (appId) async => appId == null
///         ? const RateLimitPolicy(maxRequests: 20, window: Duration(minutes: 5))
///         : await planPolicyFor(appId),
///   ),
///   RateLimitCounter(
///     name: 'device',
///     column: schema.installId,
///     policy: (_) async =>
///         const RateLimitPolicy(maxRequests: 20, window: Duration(minutes: 5)),
///   ),
/// ];
/// ```
///
/// ## Where the key comes from
///
/// Only from [column], read out of the row the caller submitted. The caller
/// cannot name a different column, header or value to be counted under.
///
/// The value is used when it is a non-empty string or a number. When it is
/// missing, empty, any other type, or differs between the rows of one
/// `createMany`, the create has no key: it is counted on the caller's IP
/// address in this counter's own bucket, and [policy] is called with `null`.
///
/// ## Rotating keys
///
/// The value comes from the caller, so a caller can send a new one on every
/// request. Without [key], each new value starts a fresh counter. Pass [key]
/// to map the raw value to the identity you trust, such as the id of the app
/// an API key belongs to, and return `null` for a value you don't recognise.
/// A `null` from [key] is treated like a missing value: counted on the
/// caller's IP with `policy(null)`. A counter whose [key] is left out is only
/// a guard against honest overuse of one key; pair it with a counter whose
/// key the caller cannot invent.
///
/// [key] and [policy] run in the rate-limit worker on every create, so keep
/// them cheap. The worker is a long-lived process, so a lookup they make can
/// be cached there.
final class RateLimitCounter {
  RateLimitCounter({
    required this.name,
    required rd.Column<dynamic, dynamic> column,
    required this.policy,
    this.key,
  }) : columnName = column.name {
    if (!_validName.hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'must be lowercase letters, digits and underscores, starting with a '
            'letter',
      );
    }
  }

  static final _validName = RegExp(r'^[a-z][a-z0-9_]*$');

  /// Names this counter's bucket. Keep it stable: renaming it starts every
  /// key on a fresh counter. Unique within one table.
  final String name;

  /// The column of the submitted row whose value keys this counter.
  final String columnName;

  /// Maps the row's value to the key it is counted under, or `null` when the
  /// table doesn't recognise it. Left out, the value itself is the key.
  final Future<String?> Function(String value)? key;

  /// The policy for [key]'s counter, or `null` to leave it unlimited.
  ///
  /// The key is `null` when the create had no usable value (see the class
  /// docs) and is being counted on the caller's IP address instead.
  final Future<RateLimitPolicy?> Function(String? key) policy;
}
