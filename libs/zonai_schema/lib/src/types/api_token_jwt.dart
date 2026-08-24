import 'package:clock/clock.dart';
import 'package:zonai_schema/src/types/api_token_id.dart';
import 'package:zonai_schema/src/types/api_token_scope.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';

/// The identity a resolved API token acts under.
///
/// An API token is **not** a JWT on the wire -- it is an opaque
/// `zonai_pat_...` string whose SHA-256 is looked up in `_api_tokens`. This
/// class is what that lookup produces, and it is a [Jwt] for one reason: [Jwt]
/// is the currency of the whole authorization layer. Rules receive one, row
/// rules filter on one, and the worker IPC boundary rebuilds one from JSON
/// (`Request.fromJson` -> `Jwt.maybeFromJson`). An API-token identity that
/// were not a [Jwt] would need a parallel path through all of it.
///
/// Two properties that are load-bearing rather than incidental:
///
/// - **A signed JWT carrying [flag] must never be accepted as a bearer
///   token.** `_extractJwt` refuses one, with the same "rotate the secret"
///   log the `CRON` and `PROVISIONING` sentinels get. Accepting it would make
///   anyone who can sign a token able to mint themselves an unscoped admin
///   key. [flag] exists for the worker round trip and for nothing else.
/// - **[admin] is exempt from `_withServerDerivedAdmin`.** That check exists
///   because a JWT's `admin` field arrives on the wire and was once trusted
///   verbatim; it re-derives the answer from the auth table's `AsAdmin`
///   mixin. An unbound API token has no table to derive from -- and does not
///   need one, because its powers come from a `_api_tokens` row that only an
///   existing admin (or someone with filesystem access to the database) could
///   have written. The safety property is server-side state either way; only
///   the route to it differs.
final class ApiTokenJwt implements Jwt {
  ApiTokenJwt({
    required this.tokenId,
    required this.name,
    required this.scope,
    Map<String, Object?> claims = const {},
    this.boundTable,
    this.boundUserId,
    Map<String, Object?> boundUser = const {},
    this.revokesAt,
  }) : claims = Map.unmodifiable(claims),
       user = Map.unmodifiable(boundUser);

  factory ApiTokenJwt.fromJson(Map<String, Object?> json) {
    return ApiTokenJwt(
      tokenId: ApiTokenId(json['tokenId']! as String),
      name: json['name'] as String? ?? '',
      scope: switch (json['scope']) {
        final Map<String, Object?> scope => ApiTokenScope.fromJson(scope),
        final Map<Object?, Object?> scope => ApiTokenScope.fromJson(
          scope.map((key, value) => MapEntry('$key', value)),
        ),
        _ => ApiTokenScope.none,
      },
      claims: switch (json['claims']) {
        final Map<Object?, Object?> claims => claims.map(
          (key, value) => MapEntry('$key', value),
        ),
        _ => const {},
      },
      boundTable: json['boundTable'] as String?,
      boundUserId: switch (json['boundUserId']) {
        final String id => UnknownId(id),
        _ => null,
      },
      boundUser: switch (json['user']) {
        final Map<Object?, Object?> user => user.map(
          (key, value) => MapEntry('$key', value),
        ),
        _ => const {},
      },
      revokesAt: switch (json['expiresAt']) {
        final num seconds => DateTime.fromMillisecondsSinceEpoch(
          seconds.toInt() * 1000,
          isUtc: true,
        ),
        _ => null,
      },
    );
  }

  /// Distinguishes an API-token payload at the worker boundary, in the same
  /// shape as `CronJwt`'s `'CRON'` and `ProvisioningJwt`'s `'PROVISIONING'`.
  /// See [Jwt.fromJson] and the class doc above.
  static bool isApiTokenPayload(Map<String, Object?> json) =>
      json[flag] == true;

  static const flag = 'API_TOKEN';

  /// [table] and [userId] for a token bound to no auth row.
  ///
  /// A rule doing `row.ownerId == jwt.userId` matches nothing under an
  /// unbound token. That is correct -- the token owns no rows -- and it is
  /// the surprise, so it is worth saying out loud in the docs rather than
  /// letting someone discover it as an empty list.
  static const sentinel = '__api_token__';

  /// The instant an unexpiring token would expire, were it able to.
  ///
  /// [Jwt.expiresAt] is non-nullable and `Jwt.fromJson` multiplies it, so
  /// "never" has no representation in that type. [revokesAt] carries the real
  /// answer; this is what [expiresAt] shows a caller that only knows [Jwt].
  static final never = DateTime.utc(9999, 12, 31);

  final ApiTokenId tokenId;

  /// The human label from the row -- "nightly-backup", "vercel-preview".
  /// Carried onto the identity so rules and logs can name the caller.
  final String name;

  final ApiTokenScope scope;

  /// The auth collection this token acts as a row of, or null when it is a
  /// standalone service identity.
  final String? boundTable;
  final UnknownId? boundUserId;

  /// When the token stops working, or null for never.
  final DateTime? revokesAt;

  bool get neverExpires => revokesAt == null;

  @override
  ({bool? canEdit, bool isAdmin}) get admin => scope.admin
      // `canEdit` is only meaningful alongside `isAdmin`, the same way
      // `AsAdmin.canEdit` is only reachable on an admin table. Token creation
      // refuses `canEdit` without `admin` for the same reason; this is the
      // second line of that defence, for a row edited by hand.
      ? (isAdmin: true, canEdit: scope.canEdit)
      : (isAdmin: false, canEdit: null);

  @override
  final Map<String, Object?> claims;

  @override
  DateTime get expiresAt => revokesAt ?? never;

  @override
  bool get isExpired {
    if (revokesAt case final revokesAt?) {
      return clock.now().isAfter(revokesAt);
    }
    return false;
  }

  @override
  JwtId get jwtId => JwtId('$sentinel:${tokenId.value}');

  @override
  String get table => boundTable ?? sentinel;

  @override
  UnknownId get userId => boundUserId ?? const UnknownId(sentinel);

  @override
  final Map<String, Object?> user;

  @override
  Map<String, dynamic> toJson() => {
    flag: true,
    'tokenId': tokenId.value,
    'name': name,
    'scope': scope.toJson(),
    'claims': claims,
    'boundTable': ?boundTable,
    'boundUserId': ?boundUserId?.value,
    'user': user,
    'expiresAt': ?_expiresAtSeconds,
  };

  /// Epoch seconds, matching [Jwt.toJson]'s encoding of the same field, or
  /// null when the token never expires.
  int? get _expiresAtSeconds => switch (revokesAt) {
    final revokesAt? => revokesAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    null => null,
  };
}
