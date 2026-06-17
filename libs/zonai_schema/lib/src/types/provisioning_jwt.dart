import 'package:zonai_schema/src/types/id.dart';
import 'package:zonai_schema/src/types/jwt.dart';
import 'package:zonai_schema/src/types/jwt_id.dart';

/// Internal sentinel identity used while running the
/// `onExternalAuthFirstSeen` extension hook to insert a missing
/// auth-table row for a verified external IdP user.
///
/// Behaves like [Jwt] with `isAdmin: true` / `canEdit: true` — but
/// the rules layer additionally restricts mutations carried by a
/// `ProvisioningJwt` to the single [authTable] declared at
/// construction. A hook running under this JWT cannot mutate any
/// other collection in the database.
///
/// Must NEVER be issued in response to a client bearer token. It is
/// constructed internally by the runtime when invoking the
/// provisioning hook and is recognized on the wire by the
/// `'PROVISIONING'` flag in its JSON form, in the same shape as
/// [CronJwt]'s `'CRON'` flag.
final class ProvisioningJwt implements Jwt {
  ProvisioningJwt({required this.authTable});

  /// The single auth collection mutations are permitted against
  /// during the provisioning hook. Rules reject any mutation
  /// targeting a different table.
  final String authTable;

  /// Distinguishes a `ProvisioningJwt` payload from a real user JWT
  /// at the worker boundary. See [Jwt.fromJson].
  static bool isProvisioningPayload(Map<String, Object?> json) =>
      json['PROVISIONING'] == true;

  @override
  ({bool? canEdit, bool isAdmin}) get admin => (isAdmin: true, canEdit: true);

  @override
  Map<String, Object?> get claims => const {};

  @override
  DateTime get expiresAt => DateTime.now().add(const Duration(minutes: 1));

  @override
  bool get isExpired => false;

  @override
  JwtId get jwtId => JwtId('__provisioning__:$authTable');

  @override
  String get table => authTable;

  @override
  Map<String, Object?> get user => const {};

  @override
  UnknownId get userId => UnknownId('__provisioning__');

  @override
  Map<String, dynamic> toJson() => {
    'PROVISIONING': true,
    'authTable': authTable,
  };
}
