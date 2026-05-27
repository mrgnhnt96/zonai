library zonai_db;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:file/file.dart';
import 'package:raindrop/raindrop.dart' as raindrop show migrate;
import 'package:raindrop/raindrop.dart' hide migrate;
import 'package:raindrop_sqlite/raindrop_sqlite.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/db_mutator/worker_process_failed_exception.dart';
import 'package:zonai/src/db_mutator/objected_row.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/mutations.dart';
import 'package:zonai/src/internal/tables/photos_table.dart';
import 'package:zonai/src/native/resqlite_native.dart';
import 'package:zonai/src/utils/hash_password.dart';
import 'package:zonai/src/utils/jwt_generator.dart';
import 'package:zonai_schema/src/handlers/config/config_request.dart';
import 'package:zonai_schema/src/handlers/config/config_response.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai/src/internal/tables/auth_challenge_table.dart';
import 'package:zonai/src/internal/internal_db_artifacts.dart';
import 'package:zonai/src/internal/internal_db_migrate.dart';
import 'package:zonai/src/internal/tables/jwt_table.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger, photos, Table;

import '../operation_result.dart';
import '../payloads/payloads.dart';
import '../sqlite_internal_table_sync.dart';

part 'parts/__auth_utils.dart';
part 'parts/__utils.dart';
part 'parts/admin/create_admin.dart';
part 'parts/auth/auth.dart';
part 'parts/auth/challenge.dart';
part 'parts/auth/logout.dart';
part 'parts/auth/magic_link.dart';
part 'parts/auth/otp.dart';
part 'parts/auth/password.dart';
part 'parts/auth/reset_password.dart';
part 'parts/auth/verify_email.dart';
part 'parts/count.dart';
part 'parts/create.dart';
part 'parts/delete.dart';
part 'parts/expand.dart';
part 'parts/list.dart';
part 'parts/read.dart';
part 'parts/stream_list.dart';
part 'parts/stream_one.dart';
part 'parts/update.dart';
part 'parts/photo.dart';

typedef _CrudResult = Map<String, Object?>;
typedef _CrudListResult = List<Map<String, Object?>>;
typedef _CrudPaginatedResult = Paginated<_CrudResult>;

const _prefix = '[ZONAI_DB]';

class ZonaiDb {
  ZonaiDb()
    : _extensions = Mailman(
        debugName: 'EXTENSIONS',
        executablePath: extensions.executablePath,
        fromJson: ExtensionResponse.fromJson,
      ),
      _rules = Mailman(
        debugName: 'RULES',
        executablePath: rules.executablePath,
        fromJson: RuleResponse.fromJson,
      ),
      _operations = Mailman(
        debugName: 'OPERATIONS',
        executablePath: operations.executablePath,
        fromJson: OperationResponse.fromJson,
      ),
      _config = Mailman(
        debugName: 'CONFIG',
        executablePath: config.executablePath,
        fromJson: ConfigResponse.fromJson,
      ),
      _jwt = JwtGenerator(),
      _hashPassword = HashPassword();

  Raindrop? db;
  final Mailman<ExtensionRequest, ExtensionResponse> _extensions;
  final Mailman<RuleRequest, RuleResponse> _rules;
  final Mailman<OperationRequest, OperationResponse> _operations;
  final Mailman<ConfigRequest, ConfigResponse> _config;
  final JwtGenerator _jwt;
  final HashPassword _hashPassword;

  File? __dbFile;

  void dispose() {
    db?.close();
    db = null;
    __dbFile = null;
    _extensions.dispose();
    _rules.dispose();
    _operations.dispose();
    _config.dispose();
  }

  Future<AppConfig> getConfig() async {
    return _run(() => configResolver.resolve());
  }

  Future<_AuthResult?> authenticate(
    String table,
    AuthPayload payload,
  ) async {
    return await _run(() => _authenticate(table, payload));
  }

  Future<_AuthResult?> refreshToken(String jwt) async {
    return await _run(() => _refreshToken(jwt));
  }

  Future<void> sendResetPassword(
    String table,
    ResetPasswordAuthPayload payload,
  ) async {
    return await _run(() => _sendResetPassword(table, payload));
  }

  Future<void> sendAdminResetPassword(ResetPasswordAuthPayload payload) async {
    return await _run(() async {
      final table = await _adminCollectionFor(.password);
      await _sendResetPassword(table, payload);
    });
  }

  Future<void> sendVerifyEmail(
    String table, {
    required String email,
    Map<String, dynamic>? variables,
    Jwt? jwt,
  }) async {
    return await _run(
      () => _sendVerifyEmail(
        table,
        email: email,
        variables: variables,
        jwt: jwt,
      ),
    );
  }

  Future<void> sendOtp(
    String table,
    SendOtpAuthPayload payload, {
    Jwt? jwt,
  }) async {
    return await _run(() => _sendOtp(table, payload, callerJwt: jwt));
  }

  Future<void> sendVerifyEmailAuthenticated(
    String jwtToken,
    SendVerifyEmailAuthPayload? payload,
  ) async {
    return await _run(() async {
      final jwt = await _extractJwt(JwtPayload(jwt: jwtToken));
      if (jwt == null) {
        throw StateError('Authentication is required to send verify email');
      }

      final table = switch (jwt.admin.isAdmin) {
        true when payload != null => payload.table,
        _ => jwt.table,
      };

      final targetEmail = switch (jwt.admin.isAdmin) {
        true when payload != null => payload.email,
        _ => await _emailFromJwt(table: table, jwt: jwt),
      };
      if (targetEmail == null) {
        throw StateError('Could not determine email address');
      }

      await _sendVerifyEmail(table, email: targetEmail, jwt: jwt);
    });
  }

  Future<_AuthResult?> confirmAuth(VerifyAuthPayload payload) async {
    return await _run(() async {
      switch (payload) {
        case final VerifyOtpAuthPayload payload:
          return await _verifyOtp(payload);
        case VerifyMagicLinkAuthPayload():
          return await _verifyMagicLink(payload);
        case ConfirmResetPasswordAuthPayload():
          await _confirmResetPassword(payload);
          return null;
        case VerifyEmailAuthPayload():
          await _verifyEmail(payload);
          return null;
      }
    });
  }

  Future<_AuthResult?> authenticateAdmin(AuthPayload payload) async {
    return await _run(() => _authenticateAdmin(payload));
  }

  Future<Map<String, Object?>> createAdmin({
    required String email,
    required String password,
    Map<String, dynamic>? object,
    bool verified = true,
  }) async {
    return await _run(
      () => _createAdmin(
        email: email,
        password: password,
        object: object,
        verified: verified,
      ),
    );
  }

  Stream<List<int>> getPhoto(String id, {required String? token}) {
    return _runStream(() => _getPhoto(id, token: token));
  }

  Future<Map<String, Object?>> createPhoto({
    required String? token,
    required PhotoCreateMeta meta,
    required String? contentType,
    required Stream<List<int>> image,
  }) async {
    return await _run(
      () => _createPhoto(
        token: token,
        meta: meta,
        contentType: contentType,
        image: image,
      ),
    );
  }

  Future<void> updatePhoto({
    required String? token,
    required String id,
    required Stream<List<int>> image,
  }) async {
    return await _run(() => _updatePhoto(token: token, id: id, image: image));
  }

  Future<void> deletePhoto({required String? token, required String id}) async {
    return await _run(() => _deletePhoto(token: token, id: id));
  }

  Future<void> sendEmail(Email email) async {
    await _run(() => courier.send(email));
  }

  Future<List<AuthType>> adminSupportedAuthTypes() async {
    return await _run(_adminSupportedAuthTypes);
  }

  Future<void> logout(String jwt) async {
    return await _run(() => _logout(jwt));
  }

  Future<void> logoutAll(String jwt) async {
    return await _run(() => _logoutAll(jwt));
  }

  Future<_CrudResult> create(String table, CreatePayload payload) async {
    return await _run(() => _create(table, payload));
  }

  Future<Jwt?> parseJwt(String? jwt) async {
    return await _extractJwt(JwtPayload(jwt: jwt));
  }

  Future<_CrudListResult> update(
    String table,
    UpdatePayload payload,
  ) async {
    return await _run(() => _update(table, payload));
  }

  Future<int> delete(String table, DeletePayload payload) async {
    return await _run(() => _delete(table, payload));
  }

  Future<_CrudResult> read(String table, ViewPayload payload) async {
    return await _run(() => _read(table, payload));
  }

  Future<_CrudPaginatedResult> list(
    String table,
    ListPayload payload,
  ) async {
    return await _run(() => _list(table, payload));
  }

  Future<int> count(String table, CountPayload payload) async {
    return await _run(() => _count(table, payload));
  }

  Stream<int> streamCount(String table, CountPayload payload) async* {
    yield* await _runStream(() => _streamCount(table, payload));
  }

  Stream<Map<String, Object?>> streamOne(
    String table,
    ViewPayload payload,
  ) async* {
    yield* _runStream(() => _streamOne(table, payload));
  }

  Stream<List<Map<String, Object?>>> streamList(
    String table,
    ListPayload payload,
  ) async* {
    yield* _runStream(() => _streamList(table, payload));
  }

  Future<T> _run<T>(Future<T> Function() body) async {
    try {
      final m = Mutations();
      return await runMergedScopedFuture(
        body,
        includeIfAbsent: {cleanUpProvider, executableStopProvider},
        override: {
          mutationsProvider.overrideWith(() => m),
          configResolverProvider.overrideWith(
            () => ConfigResolver(mailman: _config),
          ),
        },
      );
    } on ExecutableUnavailableException {
      rethrow;
    } on WorkerProcessFailedException catch (e, stack) {
      logger.error('Failed to run database operation', e, stack);
      rethrow;
    } catch (e, stack) {
      logger.error('Failed to run database operation', e, stack);
      rethrow;
    }
  }

  Stream<T> _runStream<T>(Stream<T> Function() body) async* {
    final m = Mutations();
    yield* await runMergedScopedFuture(
      () async => body(),
      includeIfAbsent: {cleanUpProvider, executableStopProvider},
      override: {
        mutationsProvider.overrideWith(() => m),
        configResolverProvider.overrideWith(
          () => ConfigResolver(mailman: _config),
        ),
      },
    );
  }
}
