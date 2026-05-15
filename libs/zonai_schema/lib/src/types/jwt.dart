import 'dart:convert';

import 'package:clock/clock.dart';

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
    required this.collection,
    required this.jwtId,
    required this.expiresAt,
    required Map<String, Object?> user,
    required Map<String, Object?> claims,
    required this.admin,
  }) : claims = Map.unmodifiable(claims),
       user = Map.unmodifiable(user);

  factory Jwt.create({
    required String userId,
    required String collection,
    required Map<String, Object?> user,
    required String jwtId,
    required Duration expiresIn,
    required Map<String, Object?> claims,
  }) {
    return Jwt(
      userId: userId,
      collection: collection,
      user: user,
      jwtId: jwtId,
      expiresAt: clock.now().add(expiresIn),
      claims: claims,
      admin: (isAdmin: false, canEdit: null),
    );
  }

  factory Jwt.fromJson(Map<String, dynamic> json) {
    return Jwt(
      userId: json['userId'],
      collection: json['collection'],
      user: json['user'] ?? {},
      jwtId: json['jwtId'],
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
      'userId': userId,
      'collection': collection,
      'jwtId': jwtId,
      'expiresAt': expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      'claims': jsonDecode(jsonEncode(claims)),
      'user': jsonDecode(jsonEncode(user)),
      'admin': {'isAdmin': admin.isAdmin, 'canEdit': ?admin.canEdit},
    };
  }

  final String userId;
  final String collection;
  final Map<String, Object?> user;
  final String jwtId;
  final ({bool isAdmin, bool? canEdit}) admin;
  final DateTime expiresAt;
  final Map<String, Object?> claims;

  bool get isExpired => clock.now().isAfter(expiresAt);

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}
