import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:zonai_schema/zonai_schema.dart';

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

  factory Jwt.fromJson(Map<String, dynamic> json) {
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
