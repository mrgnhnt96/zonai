part of '../../interfaces.dart';

abstract interface class AdminDataSource {
  const AdminDataSource();

  Future<Map<String, Object?>> members({String? authorization});
  Future<Map<String, Object?>> passwordResetRequirement({
    required String email,
    required String table,
    String? authorization,
  });
  Future<Map<String, Object?>> invite({
    required AdminInviteBody body,
    String? authorization,
  });
  Future<Map<String, Object?>> requirePasswordReset({
    required String email,
    required String table,
    String? reason,
    String? authorization,
  });
  Future<void> revokeInvite({required String email, String? authorization});
  Future<Map<String, Object?>> removeMember({
    required String email,
    String? authorization,
  });
  Future<Map<String, Object?>> clearPasswordReset({
    required String email,
    required String table,
    String? authorization,
  });
}
