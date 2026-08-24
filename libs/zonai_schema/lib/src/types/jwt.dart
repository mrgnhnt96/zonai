import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:zonai_schema/src/types/api_token_jwt.dart';
import 'package:zonai_schema/src/types/cron_jwt.dart';
import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';
import 'package:zonai_schema/src/types/provisioning_jwt.dart';

/// A JWT token for a [user].
///
/// [userId] is the ID of the user that the JWT token belongs to.
/// [collection] is the collection that the [user] belongs to.
/// [jwtId] is the ID of the JWT token.
/// [expiresAt] is the expiration date of the JWT token.
/// [user] the current user's object
/// [claims] are the claims that are included in the JWT token.
class Jwt {
  Jwt({
    required this.userId,
    required this.table,
    required this.jwtId,
    required this.expiresAt,
    required Map<String, Object?> user,
    required Map<String, Object?> claims,
    required this.admin,
  }) : claims = Map.unmodifiable(claims),
       user = Map.unmodifiable(user);

  factory Jwt.create({
    required String userId,
    required String table,
    required Map<String, Object?> user,
    required JwtId jwtId,
    required Duration expiresIn,
    required Map<String, Object?> claims,
  }) {
    return Jwt(
      userId: UnknownId(userId),
      table: table,
      user: user,
      jwtId: jwtId,
      expiresAt: clock.now().add(expiresIn),
      claims: claims,
      admin: (isAdmin: false, canEdit: null),
    );
  }

  /// Worker IPC sentinel ([CronJwt]); must not be accepted on user bearer tokens.
  static bool isCronWorkerPayload(Map<String, Object?> json) =>
      json['CRON'] == true;

  /// Worker IPC sentinel ([ProvisioningJwt]); must not be accepted on user
  /// bearer tokens.
  static bool isProvisioningWorkerPayload(Map<String, Object?> json) =>
      ProvisioningJwt.isProvisioningPayload(json);

  /// Worker IPC form of a resolved API token ([ApiTokenJwt]); must not be
  /// accepted on user bearer tokens.
  ///
  /// The credential for an API token is an opaque `zonai_pat_...` string, not
  /// a JWT. This payload exists so a resolved token survives the trip to the
  /// rules and operations workers -- accepting a *signed* one as a bearer
  /// token would let anyone holding the signing key mint an unscoped admin
  /// identity for themselves.
  static bool isApiTokenPayload(Map<String, Object?> json) =>
      ApiTokenJwt.isApiTokenPayload(json);

  factory Jwt.fromJson(Map<String, dynamic> json) {
    if (isCronWorkerPayload(json)) {
      return CronJwt();
    }
    if (isProvisioningWorkerPayload(json)) {
      return ProvisioningJwt(authTable: json['authTable'] as String);
    }
    if (isApiTokenPayload(json)) {
      return ApiTokenJwt.fromJson(json);
    }

    return Jwt(
      userId: UnknownId(json['userId']),
      table: json['table'],
      user: json['user'] ?? {},
      jwtId: JwtId(json['jwtId']),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] * 1000),
      claims: json['claims'],
      admin: switch (json['admin']) {
        {'isAdmin': true, 'canEdit': final bool? canEdit} => (
          isAdmin: true,
          canEdit: canEdit,
        ),
        _ => (isAdmin: false, canEdit: null),
      },
    );
  }

  static Jwt? maybeFromJson(dynamic json) {
    try {
      return Jwt.fromJson(json as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  static Jwt? parse(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return null;
    }

    final [_, payload, _] = parts;

    // JWTs are conventionally issued with the base64url padding stripped
    // (RFC 7515) — every token this library itself issues is unpadded (see
    // apps/zonai's JWT signing) — but `base64Url.decode` requires the input
    // length to be an exact multiple of four and throws
    // `FormatException: Invalid length, must be multiple of four` otherwise.
    // Confirmed live: this broke every real signed-in session in a browser
    // client (zonai_client's `Auth.jwt` calls this on every page load),
    // permanently, on every token the server actually issues.
    final normalized = switch (payload.length % 4) {
      0 => payload,
      final remainder => payload.padRight(
        payload.length + (4 - remainder),
        '=',
      ),
    };

    // A malformed/corrupted/tampered token can fail at any of decode, utf8,
    // JSON, or Jwt.fromJson's own field access — parse's contract (like
    // maybeFromJson's) is to return null on any such failure, not throw.
    try {
      final payloadJson = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      return Jwt.fromJson(payloadJson as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId.value,
      'table': table,
      'jwtId': jwtId.value,
      'expiresAt': expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      'claims': jsonDecode(jsonEncode(claims)),
      'user': jsonDecode(jsonEncode(user)),
      'admin': {'isAdmin': admin.isAdmin, 'canEdit': ?admin.canEdit},
    };
  }

  final UnknownId userId;
  final String table;
  final Map<String, Object?> user;
  final JwtId jwtId;
  final ({bool isAdmin, bool? canEdit}) admin;
  final DateTime expiresAt;
  final Map<String, Object?> claims;

  bool get isExpired => clock.now().isAfter(expiresAt);

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}
