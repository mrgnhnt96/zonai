import 'dart:convert';

import 'package:clock/clock.dart';

class AppJwt {
  const AppJwt({
    required this.userId,
    required this.collection,
    required this.user,
    required this.jwtId,
    required this.expiresAt,
    required this.claims,
  });

  factory AppJwt.create({
    required String userId,
    required String collection,
    required Map<String, Object?> user,
    required String jwtId,
    required Duration expiresIn,
    required Map<String, Object?> claims,
  }) {
    return AppJwt(
      userId: userId,
      collection: collection,
      user: user,
      jwtId: jwtId,
      expiresAt: clock.now().add(expiresIn),
      claims: claims,
    );
  }

  factory AppJwt.fromJson(Map<String, dynamic> json) {
    return AppJwt(
      userId: json['userId'],
      collection: json['collection'],
      user: json['user'],
      jwtId: json['jwtId'],
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] * 1000),
      claims: json['claims'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'collection': collection,
      'jwtId': jwtId,
      'expiresAt': expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
      'claims': jsonDecode(jsonEncode(claims)),
    };
  }

  final String userId;
  final String collection;
  final Map<String, Object?> user;
  final String jwtId;
  final DateTime expiresAt;
  final Map<String, Object?> claims;

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}
