library zonai_db;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:file/file.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/raindrop_sqlite.dart'
    show SQLiteInsertReturning, SQLiteDeleteReturning;
import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart'
    as raindrop
    show migrate;
import 'package:zonai/src/db_mutator/zonai_db/resqlite/resqlite_delegate.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/src/db_mutator/host_worker_registries.dart';
import 'package:zonai/src/db_mutator/mailman.dart';
import 'package:zonai/src/db_mutator/zonai_db/concurrency_gate.dart';
import 'package:zonai/src/db_mutator/objected_row.dart';
import 'package:zonai/src/domain/constants.dart';
import 'package:zonai/src/domain/mutations.dart';
import 'package:zonai_schema/src/internal/internal_db_artifacts.dart';
import 'package:zonai/src/internal/internal_db_migrate.dart';
import 'package:zonai_schema/src/internal/tables/auth_challenge_table.dart';
import 'package:zonai_schema/src/internal/tables/jwt_table.dart';
// `show logs`: this file already has a `Level` in scope from the logger, and
// logs_table.dart exports one of its own.
import 'package:zonai_schema/src/internal/tables/logs_table.dart' show logs;
import 'package:zonai_schema/src/internal/tables/photos_table.dart';
import 'package:zonai_schema/src/internal/tables/push_jobs_table.dart';
import 'package:zonai/src/push/push_courier.dart';
// `WhereX.sql` renders a caller's predicate to a parameterized SQL fragment.
// The push fan-out needs it to splice the caller's `where` into a projection
// it builds itself -- see `parts/push.dart`. Not re-exported by the barrel.
import 'package:zonai_schema/src/types/where_sql.dart';
import 'package:zonai_schema/src/internal/tables/rate_limit_table.dart'
    show rateLimits;
import 'package:zonai/src/messengers/config_mailman.dart';
import 'package:zonai/src/messengers/cron_mailman.dart';
import 'package:zonai/src/messengers/extensions_mailman.dart';
import 'package:zonai/src/messengers/operations_mailman.dart';
import 'package:zonai/src/messengers/rules_mailman.dart';
import 'package:zonai/src/native/resqlite_native.dart';
import 'package:zonai/src/utils/hash_password.dart';
import 'package:zonai/src/utils/jwks_idp_verifier.dart';
import 'package:zonai/src/utils/jwt_generator.dart';
import 'package:zonai/src/utils/format_bytes.dart';
import 'package:zonai/src/utils/free_disk_space.dart';
import 'package:zonai/src/utils/photo_stream_utils.dart';
import 'package:zonai/src/utils/shared_secret_idp_verifier.dart';
import 'package:zonai_schema/src/handlers/cron/cron_request.dart';
import 'package:zonai_schema/src/handlers/cron/cron_response.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_request.dart';
import 'package:zonai_schema/src/handlers/extensions/extension_response.dart';
import 'package:zonai_schema/src/handlers/operations/operation_request.dart';
import 'package:zonai_schema/src/handlers/operations/operation_response.dart';
import 'package:zonai_schema/src/handlers/rules/rule_request.dart';
import 'package:zonai_schema/src/handlers/rules/rule_response.dart';
import 'package:zonai_schema/zonai_schema.dart' hide logger, photos, Table;

import '../operation_result.dart';
import '../payloads/payloads.dart';
import '../sqlite_internal_table_sync.dart';

part 'parts/__auth_utils.dart';
part 'parts/__utils.dart';
part 'parts/admin/create_admin.dart';
part 'parts/admin/list_admins.dart';
part 'parts/admin/remove_admin.dart';
part 'parts/admin/reset_admin_password.dart';
part 'parts/auth/auth.dart';
part 'parts/auth/challenge.dart';
part 'parts/auth/external_idp.dart';
part 'parts/auth/logout.dart';
part 'parts/auth/magic_link.dart';
part 'parts/auth/otp.dart';
part 'parts/auth/password.dart';
part 'parts/auth/reset_password.dart';
part 'parts/auth/verify_email.dart';
part 'parts/cleanup_photos.dart';
part 'parts/clear_logs.dart';
part 'parts/count.dart';
part 'parts/create.dart';
part 'parts/custom.dart';
part 'parts/dashboard_metrics.dart';
part 'parts/run_cron_job.dart';
part 'parts/list_cron_jobs.dart';
part 'parts/delete.dart';
part 'parts/effects.dart';
part 'parts/expand.dart';
part 'parts/list.dart';
part 'parts/photo.dart';
part 'parts/purge.dart';
part 'parts/push.dart';
part 'parts/read.dart';
part 'parts/reclaim_log_space.dart';
part 'parts/resolve_photos.dart';
part 'parts/stream_list.dart';
part 'parts/stream_one.dart';
part 'parts/update.dart';

typedef _CrudResult = Map<String, Object?>;
typedef _CrudListResult = List<Map<String, Object?>>;
typedef _CrudPaginatedResult = Paginated<_CrudResult>;

const _prefix = '[ZONAI_DB]';

/// The `_log` table's SQLite name.
///
/// Always used unqualified in statements: it lives in the attached
/// [kLogDbSchema] database, and an unqualified name resolves there because
/// `main` no longer has a table by that name (see `_ensureDisposableTables`).
final _logTableName = logs.$.name;

/// Internal tables that live in a database file of their own, and the schema
/// each is attached under.
///
/// "Disposable" is the property that earns the split, and it is a real one
/// rather than a tidiness argument: high churn, bounded retention, and
/// nothing worth reconstructing after a crash. That combination is what makes
/// `unlink` a legitimate recovery step, keeps `VACUUM`'s exclusive lock off
/// application data, and makes a page cap expressible at all -- a cap bounds
/// a *file*, so on the shared database it would be hit by whichever write
/// arrived first, application inserts included.
///
/// `_auth_challenges` and `_cron_jobs` are the next candidates; see the
/// "table groups" entry in todo.md for the general version, which would let a
/// schema declare this instead of it being listed here.
final _disposableTableSchemas = <String, String>{
  logs.$.name: kLogDbSchema,
  rateLimits.$.name: kRateLimitDbSchema,
};

/// Indexes to recreate in the attached file, keyed by table.
///
/// These exist in the generated migrations too, but those ran against `main`
/// and were dropped along with the table when it moved. `$schema` is
/// substituted with the attached schema name -- an index has to be created in
/// the same database as its table.
final _disposableTableIndexes = <String, List<String>>{
  logs.$.name: [
    'CREATE UNIQUE INDEX IF NOT EXISTS "\$schema"."log_id_unique" '
        'ON "${logs.$.name}" ("id")',
    'CREATE INDEX IF NOT EXISTS "\$schema"."log_level_timestamp_index" '
        'ON "${logs.$.name}" ("level", "timestamp")',
  ],
  rateLimits.$.name: [
    // The rate limiter depends on this one for correctness, not just speed:
    // it retries an insert on constraint violation 19 to resolve the race
    // between two concurrent requests both missing the same bucket row.
    'CREATE UNIQUE INDEX IF NOT EXISTS "\$schema"."rate_limit_bucket_unique" '
        'ON "${rateLimits.$.name}" ("client_ip", "table", "operation")',
  ],
};

class ZonaiDb {
  /// [configResolver] replaces the config worker for tests.
  ///
  /// [_run] overrides `configResolverProvider` on every call, so a scope-level
  /// override outside it is ignored — which meant that until this existed,
  /// exercising anything that reads `AppConfig` required compiling a config
  /// worker. That is the same missing seam `PushCourier` exists to avoid on
  /// the transport side.
  ZonaiDb({@visibleForTesting ConfigResolver? configResolver})
    : _fixedConfigResolver = configResolver,
      _extensions = MailmanPool(ExtensionsMailman.new),
      _rules = MailmanPool(RulesMailman.new),
      _operations = MailmanPool(OperationsMailman.new),
      _config = ConfigMailman(),
      _jwt = JwtGenerator(),
      _hashPassword = HashPassword();

  Raindrop? db;

  /// Serializes concurrent [open] calls. resqlite segfaults if the same file
  /// is opened twice in parallel.
  Future<Raindrop>? _opening;

  // Pooled: every list/get/create/update/delete round-trips through rules
  // (access checks) and often operations (SQL building) and extensions
  // (hooks), each normally a single OS subprocess. One process serializes
  // every request behind one stdin/stdout pipe regardless of concurrency;
  // pooling spreads them across a handful of independent processes instead.
  // Not done for [ConfigMailman] (config resolution isn't the hot path
  // here) or the cron worker (a singleton scheduler -- pooling it would run
  // every job N times). See [MailmanPool]'s doc comment.
  final MailmanPool<ExtensionRequest, ExtensionResponse, ExtensionsMailman>
  _extensions;
  final MailmanPool<RuleRequest, RuleResponse, RulesMailman> _rules;
  final MailmanPool<OperationRequest, OperationResponse, OperationsMailman>
  _operations;
  final ConfigMailman _config;

  /// Set only by tests; see the constructor.
  final ConfigResolver? _fixedConfigResolver;
  final JwtGenerator _jwt;
  final HashPassword _hashPassword;

  /// Host-side caches so repeated list/get calls avoid Mailman IPC after the
  /// first resolve. Cleared implicitly when this [ZonaiDb] is disposed (new
  /// process / worker recompile restarts the server).
  /// Table-rule verdicts with the time each was decided, so
  /// [UtilsX._cachedTableRules] can expire one instead of serving it forever.
  final Map<String, ({TableRulesResponse response, DateTime at})>
  _tableAccessCache = {};
  final Map<String, bool> _skipRowChecks = {};
  final Map<String, PerformOperationResponse> _operationCache = {};
  final Map<String, ({List<String> secretColumns, List<String> photoColumns})>
  _sanitizeMetaCache = {};
  final Map<String, String?> _columnNameCache = {};

  /// Schema-derived admin powers per auth table, consulted by `_validateJwt`
  /// on every authenticated request. Safe to cache for the process lifetime:
  /// `AsAdmin` is declared in source, so changing it means a recompile and a
  /// restart.
  final Map<String, ({bool isAdmin, bool canEdit})> _adminStatusCache = {};

  /// Lazily detected: when the project has no extension Dart files (and no
  /// internal extensions), create/update/delete skip the extensions worker
  /// entirely.
  bool? _hasProjectExtensions;

  /// The most recently started push drain, or null if none has run.
  ///
  /// Each new drain awaits this one before starting, so passes serialize and
  /// every caller gets a pass that began after their call. See
  /// `_PushX._drainPushJobs`.
  Future<_DrainPushResult>? _pushDrain;

  /// Serializes mutating work so concurrent creates don't pile into
  /// SQLite's 5s busy_timeout. Excess waiters fail fast with 503.
  Future<void>? _writeChain;
  var _pendingWrites = 0;
  static const _maxQueuedWrites = 64;

  /// Caps concurrent read-path work (read/list/count). Reads aren't
  /// serialized like writes -- this just bounds how many can be in flight
  /// at once so a large enough burst fails fast with 503 instead of queueing
  /// unboundedly behind the rules-worker's single pipe (see the MailmanPool
  /// comment above). Set well above documented/benchmarked concurrency
  /// (stress/README.md's sweeps go up to 100) so normal load never trips it.
  static const _maxQueuedReads = 256;
  final ConcurrencyGate _readGate = ConcurrencyGate(
    maxConcurrent: _maxQueuedReads,
    onSaturated: () => const ReadBackpressureException(),
  );

  /// Keyed by `JwksIdpConfig.jwksUrl` so multiple configs against the
  /// same endpoint share a key cache and HTTP client. Constructed
  /// lazily by [_jwksVerifierFor]; disposed in [dispose].
  final Map<String, JwksIdpVerifier> _jwksVerifiers = {};

  File? __dbFile;
  File? __logDbFile;
  File? __rateLimitDbFile;

  /// Closes the underlying [ResqliteDelegate] and clears the open [db].
  Future<void> close() async {
    final db = this.db;
    this.db = null;
    _opening = null;
    if (db?.delegate case ResqliteDelegate delegate) {
      await delegate.close();
    }
  }

  Future<void> dispose() async {
    await close();
    __dbFile = null;
    __logDbFile = null;
    __rateLimitDbFile = null;
    _extensions.dispose();
    _rules.dispose();
    _operations.dispose();
    _config.dispose();
    _tableAccessCache.clear();
    _skipRowChecks.clear();
    _operationCache.clear();
    _sanitizeMetaCache.clear();
    _columnNameCache.clear();
    _adminStatusCache.clear();
    _hasProjectExtensions = null;
    for (final verifier in _jwksVerifiers.values) {
      verifier.dispose();
    }
    _jwksVerifiers.clear();
  }

  Future<AppConfig> getConfig() async {
    return _run(() => configResolver.resolve());
  }

  Future<_AuthResult?> authenticate(String table, AuthPayload payload) async {
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
      () =>
          _sendVerifyEmail(table, email: email, variables: variables, jwt: jwt),
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

  Future<String> adminPasswordTable() async {
    return await _run(() => _adminCollectionFor(.password));
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

  Future<Map<String, Object?>> resetAdminPassword({
    required String email,
    required String newPassword,
  }) async {
    return await _run(
      () => _resetAdminPassword(email: email, newPassword: newPassword),
    );
  }

  Future<Map<String, Object?>> removeAdmin({required String email}) async {
    return await _run(() => _removeAdmin(email: email));
  }

  Future<List<Map<String, Object?>>> listAdmins() async {
    return await _run(() => _listAdmins());
  }

  /// Deletes log rows, optionally only those recorded before [before].
  /// Returns the number of rows removed.
  Future<int> clearLogs({DateTime? before}) async {
    return await _runWrite(() => _clearLogs(before: before));
  }

  /// Bulk-deletes rows from one of the framework's own tables, returning how
  /// many were removed. Serialized with other writes like any mutation.
  ///
  /// See [_purge] for why this may skip per-row rules, and which tables it
  /// refuses.
  Future<int> purge({
    required String table,
    required Where where,
    required Jwt? jwt,
  }) async {
    return await _runWrite(() => _purge(table: table, where: where, jwt: jwt));
  }

  /// Rewrites a database file so space freed by deletes is returned to the
  /// operating system. Serialized against other writes: the rewrite takes an
  /// exclusive lock for its duration, so letting it interleave would just
  /// push concurrent writers into SQLite's busy timeout.
  ///
  /// [schema] picks the file — `null` for the application database,
  /// [kLogDbSchema] for the log database. See [_vacuum].
  Future<void> vacuum({String? schema}) async {
    return await _runWrite(() => _vacuum(schema: schema));
  }

  /// Rewrites the log database if enough of it is dead space and the volume
  /// has room, reporting what it did either way. See [_reclaimLogSpace].
  ///
  /// Serialized like any other write: the rewrite takes an exclusive lock.
  Future<LogSpaceReclamation> reclaimLogSpace() async {
    return await _runWrite(() => _reclaimLogSpace());
  }

  Future<File> getPhoto(String id, {required String? token}) {
    return _run(() => _getPhoto(id, token: token));
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

  Future<int> cleanupUnreferencedPhotos() async {
    return await _run(_cleanupUnreferencedPhotos);
  }

  /// Records a push fan-out, returning its id — or null when the project has
  /// no `AppConfig.push`.
  Future<PushJobId?> enqueuePush({
    required PushMessage message,
    required String table,
    required String column,
    required Where? where,
    required Jwt? jwt,
    String? platformColumn,
  }) async {
    return await _run(
      () => _enqueuePush(
        message: message,
        table: table,
        column: column,
        where: where,
        jwt: jwt,
        platformColumn: platformColumn,
      ),
    );
  }

  Future<_DrainPushResult> drainPushJobs() async {
    return await _run(_drainPushJobs);
  }

  Future<DashboardMetrics> dashboardMetrics({
    required Jwt jwt,
    int? since,
    bool excludeAdmin = false,
  }) async {
    return await _run(
      () =>
          _dashboardMetrics(jwt: jwt, since: since, excludeAdmin: excludeAdmin),
    );
  }

  Future<void> runCronJob({required Jwt jwt, required String name}) async {
    return await _run(() => _runCronJob(jwt: jwt, name: name));
  }

  Future<List<String>> listCronJobs({required Jwt jwt}) async {
    return await _run(() => _listCronJobs(jwt: jwt));
  }

  Future<void> sendEmail(Email email) async {
    await _run(() => courier.send(email));
  }

  Future<List<AuthType>> adminSupportedAuthTypes() async {
    return await _run(_adminSupportedAuthTypes);
  }

  Future<Map<String, TableSchemaShape>> schemaShapes() async {
    return await _run(() async {
      final response = await _dispatchOperation<AllTableSchemaShapesResponse>(
        GetAllTableSchemaShapesRequest(),
      );
      return response.shapes;
    });
  }

  Future<Map<String, TableCollectionActions>> collectionActions({
    Jwt? jwt,
  }) async {
    return await _run(() async {
      final response = await _dispatchRules<AllTableCollectionActionsResponse>(
        GetAllTableCollectionActionsRequest(jwt: jwt),
      );
      return response?.actions ?? const {};
    });
  }

  Future<void> logout(String jwt) async {
    return await _run(() => _logout(jwt));
  }

  Future<void> logoutAll(String jwt) async {
    return await _run(() => _logoutAll(jwt));
  }

  Future<_CrudResult> create(String table, CreatePayload payload) async {
    // Hash Argon2 outside the writer lock so concurrent creates aren't
    // serialized behind password hashing.
    return await _run(() async {
      final jwt = await _extractJwt(payload);
      final changed = await _hashPasswordCreate(table, payload.object);
      if (changed) {
        if (jwt == null || !jwt.admin.isAdmin || jwt.admin.canEdit == false) {
          throw PasswordUpdateForbiddenException(table: table);
        }
      }
      return await _enqueueWrite(() => _create(table, payload));
    });
  }

  Future<_CrudListResult> createMany(
    String table,
    CreateManyPayload payload,
  ) async {
    return await _run(() async {
      final jwt = await _extractJwt(payload);
      var anyPasswordHashed = false;
      for (final object in payload.objects) {
        if (await _hashPasswordCreate(table, object)) {
          anyPasswordHashed = true;
        }
      }
      if (anyPasswordHashed) {
        if (jwt == null || !jwt.admin.isAdmin || jwt.admin.canEdit == false) {
          throw PasswordUpdateForbiddenException(table: table);
        }
      }
      return await _enqueueWrite(() => _createMany(table, payload));
    });
  }

  Future<Jwt?> parseJwt(String? jwt) async {
    return await _run(() => _extractJwt(JwtPayload(jwt: jwt)));
  }

  Future<Jwt?> parseJwtClaimsOnly(String? jwt) async {
    return await _run(() => _extractJwtClaimsOnly(jwt));
  }

  Future<_CrudListResult> update(String table, UpdatePayload payload) async {
    return await _runWrite(() => _update(table, payload));
  }

  Future<_CrudListResult> custom(String table, CustomPayload payload) async {
    return await _runWrite(() => _custom(table, payload));
  }

  Future<int> delete(String table, DeletePayload payload) async {
    return await _runWrite(() => _delete(table, payload));
  }

  Future<_CrudResult> read(String table, ViewPayload payload) async {
    return await _runRead(() => _read(table, payload));
  }

  Future<_CrudPaginatedResult> list(String table, ListPayload payload) async {
    return await _runRead(() => _list(table, payload));
  }

  Future<int> count(String table, CountPayload payload) async {
    return await _runRead(() => _count(table, payload));
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
        includeIfAbsent: {
          cleanUpProvider,
          executableStopProvider,
          externalIdpProvisioningGateProvider,
          // Every DB operation funnels through here, including the four
          // fire-and-forget email sends whose only signal to an operator is a
          // log line. `logger` reads without an `orElse`, so a caller that
          // registered no logger would trade the missing warning for a
          // `StateError` on a future nobody awaits. Absent one, this falls
          // back to a default `Logger` -- warnings still reach stderr.
          loggerProvider,
        },
        override: {
          mutationsProvider.overrideWith(() => m),
          configResolverProvider.overrideWith(
            () => _fixedConfigResolver ?? ConfigResolver(mailman: _config),
          ),
        },
      );
    } on ExecutableUnavailableException {
      rethrow;
    } on WorkerProcessFailedException {
      rethrow;
    } on AuthException {
      rethrow;
    } on CrudException {
      rethrow;
    } on PhotoException {
      rethrow;
    } on SchemaException {
      rethrow;
    } on PermissionException {
      rethrow;
    } on WriteBackpressureException {
      rethrow;
    } catch (e, stack) {
      final mapped = mapDatabaseError(
        e,
        table: 'unknown',
        orElse: (cause) =>
            StateError('Failed to run database operation: $cause'),
      );
      Error.throwWithStackTrace(mapped, stack);
    }
  }

  /// Runs [body] on a single-writer queue. Prevents concurrent creates from
  /// stacking into SQLite's 5s `busy_timeout`; when the queue is saturated,
  /// fails immediately with [WriteBackpressureException] (HTTP 503).
  Future<T> _runWrite<T>(Future<T> Function() body) async {
    return _enqueueWrite(() => _run(body));
  }

  /// Like [_runWrite] but does not open a new riverpod scope — for use when
  /// already inside [_run] (e.g. hash Argon2, then serialize only the INSERT).
  Future<T> _enqueueWrite<T>(Future<T> Function() body) async {
    if (_pendingWrites >= _maxQueuedWrites) {
      throw const WriteBackpressureException();
    }
    _pendingWrites++;
    final previous = _writeChain;
    final done = Completer<void>();
    _writeChain = done.future;
    try {
      await previous;
      return await body();
    } finally {
      _pendingWrites--;
      done.complete();
    }
  }

  /// Runs [body], failing immediately with [ReadBackpressureException]
  /// (HTTP 503) if too many reads are already concurrently in flight.
  /// Unlike [_runWrite], admitted reads run concurrently, not serialized --
  /// this only bounds *how many* can be in flight at once.
  Future<T> _runRead<T>(Future<T> Function() body) {
    return _readGate.run(() => _run(body));
  }

  Stream<T> _runStream<T>(Stream<T> Function() body) async* {
    try {
      final m = Mutations();
      yield* await runMergedScopedFuture(
        () async => body(),
        includeIfAbsent: {
          cleanUpProvider,
          executableStopProvider,
          externalIdpProvisioningGateProvider,
          // Kept in step with [_run]'s set.
          loggerProvider,
        },
        override: {
          mutationsProvider.overrideWith(() => m),
          configResolverProvider.overrideWith(
            () => _fixedConfigResolver ?? ConfigResolver(mailman: _config),
          ),
        },
      );
    } on ExecutableUnavailableException {
      rethrow;
    } on WorkerProcessFailedException {
      rethrow;
    } on AuthException {
      rethrow;
    } on CrudException {
      rethrow;
    } on PhotoException {
      rethrow;
    } on SchemaException {
      rethrow;
    } on PermissionException {
      rethrow;
    } catch (e, stack) {
      final mapped = mapDatabaseError(
        e,
        table: 'unknown',
        orElse: (cause) => StateError('Failed to run database stream: $cause'),
      );
      Error.throwWithStackTrace(mapped, stack);
    }
  }
}
