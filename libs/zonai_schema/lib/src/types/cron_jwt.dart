import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';

final class CronJwt implements Jwt {
  CronJwt();

  @override
  ({bool? canEdit, bool isAdmin}) get admin => (isAdmin: true, canEdit: true);

  @override
  Map<String, Object?> get claims => {};

  @override
  DateTime get expiresAt => .now().add(Duration(days: 365));

  @override
  bool get isExpired => false;

  @override
  JwtId get jwtId => JwtId('__cron__');

  @override
  String get table => '__cron__';

  @override
  Map<String, dynamic> toJson() {
    return {'CRON': true};
  }

  @override
  Map<String, Object?> get user => {};

  @override
  UnknownId get userId => UnknownId('__cron__');
}
