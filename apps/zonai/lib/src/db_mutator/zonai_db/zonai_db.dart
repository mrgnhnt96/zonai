library zonai_db;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:file/file.dart';
import 'package:meta/meta.dart' show visibleForTesting;
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
// The extra-column rules `zonai db admin add` already applies. Imported here
// so invite acceptance asks for exactly the set that command asks for -- two
// implementations of "what does an admin row need" is how the CLI and the
// invite screen end up disagreeing about a required column.
import 'package:zonai/src/utils/admin_create_shape.dart';
import 'package:zonai/src/domain/mutations.dart';
import 'package:zonai_schema/src/internal/internal_db_artifacts.dart';
import 'package:zonai/src/internal/internal_db_migrate.dart';
import 'package:zonai_schema/src/internal/tables/auth_challenge_table.dart';
import 'package:zonai_schema/src/internal/tables/jwt_table.dart';
import 'package:zonai_schema/src/internal/tables/oauth_identity_table.dart';
// `show logs`: this file already has a `Level` in scope from the logger, and
// logs_table.dart exports one of its own.
import 'package:zonai_schema/src/internal/tables/logs_table.dart' show logs;
import 'package:zonai_schema/src/internal/tables/photos_table.dart';
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
import 'package:zonai/src/utils/oauth/apple_client_secret_signer.dart';
import 'package:zonai/src/utils/oauth/github_email_resolver.dart';
import 'package:zonai/src/utils/oauth/oauth_authorization_url_builder.dart';
import 'package:zonai/src/utils/oauth/oauth_exception.dart';
import 'package:zonai/src/utils/oauth/oauth_id_token_verifier.dart';
import 'package:zonai/src/utils/oauth/oauth_identity.dart' as oauth_claims;
import 'package:zonai/src/utils/oauth/oauth_pkce.dart';
import 'package:zonai/src/utils/oauth/oauth_provider_credentials.dart';
import 'package:zonai/src/utils/oauth/oauth_token_exchange_client.dart';
import 'package:zonai/src/utils/oauth/oauth_userinfo_client.dart';
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
part 'parts/admin/invite_admin.dart';
part 'parts/admin/list_admins.dart';
part 'parts/admin/remove_admin.dart';
part 'parts/admin/reset_admin_password.dart';
part 'parts/auth/auth.dart';
part 'parts/auth/challenge.dart';
part 'parts/auth/external_idp.dart';
part 'parts/auth/logout.dart';
part 'parts/auth/magic_link.dart';
part 'parts/auth/oauth.dart';
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
  ZonaiDb()
    : _extensions = MailmanPool(ExtensionsMailman.new),
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
  final JwtGenerator _jwt;
  final HashPassword _hashPassword;

  /// Host-side caches so repeated list/get calls avoid Mailman IPC after the
  /// first resolve. Cleared implicitly when this [ZonaiDb] is disposed (new
  /// process / worker recompile restarts the server).
  final Map<String, TableRulesResponse> _tableAccessCache = {};
  final Map<String, bool> _skipRowChecks = {};
  final Map<String, PerformOperationResponse> _operationCache = {};
  final Map<String, ({List<String> secretColumns, List<String> photoColumns})>
  _sanitizeMetaCache = {};
  final Map<String, String?> _columnNameCache = {};

  /// Lazily detected: when the project has no extension Dart files (and no
  /// internal extensions), create/update/delete skip the extensions worker
  /// entirely.
  bool? _hasProjectExtensions;

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

  /// Shared across every Apple token exchange this [ZonaiDb] performs, so
  /// the signed client-secret JWT is cached (per team/key/client) instead
  /// of freshly ES256-signed on every request -- see
  /// [AppleClientSecretSigner]'s own caching doc.
  final AppleClientSecretSigner _appleClientSecretSigner =
      AppleClientSecretSigner();

  /// GitHub's private-primary-email fallback, held as a field for the same
  /// reason [_appleClientSecretSigner] is: it is the seam a test substitutes
  /// at.
  ///
  /// It used to be constructed inline at the one call site, which made the
  /// fallback branch unreachable from any test — the class takes an
  /// `http.Client` precisely so it can be faked, and the caller passed none.
  /// The branch is not defensive code: `GET /user` really does return
  /// `email: null` whenever the account's primary address is private, which
  /// is GitHub's own default.
  ///
  /// Deliberately NOT reachable from a stub provider. The gate on the branch
  /// is `provider is BuiltInOAuthProvider && kind == github`, and
  /// `OAuthProvider.github()` hardcodes its endpoints so a developer cannot
  /// misconfigure them — widening that factory to serve a test would invert
  /// the guarantee it exists for. In-process substitution is the seam;
  /// `github_email_resolver_live_test.dart` covers what a fake cannot, which
  /// is whether our idea of GitHub's response is right.
  @visibleForTesting
  GitHubEmailResolver githubEmailResolver = GitHubEmailResolver();

  /// The provider `userInfo` call, held here for the same reason and fixed in
  /// the same change: it was `OAuthUserInfoClient()` constructed inline inside
  /// `_identityFromTokens`, which is the step immediately before the GitHub
  /// fallback. Leaving it inline would have made the fallback substitutable
  /// but still unreachable, since nothing could produce the `email: null`
  /// response that triggers it without calling api.github.com for real.
  @visibleForTesting
  OAuthUserInfoClient oauthUserInfoClient = OAuthUserInfoClient();

  /// `_identityFromTokens`, reachable from a test.
  ///
  /// The GitHub fallback lives inside that method, and every public route to
  /// it goes through a real token exchange against the provider's own
  /// hardcoded endpoints — so without this the branch could only be exercised
  /// by talking to github.com, or by widening `OAuthProvider.github()` to
  /// accept endpoint overrides, which would undo the reason built-in
  /// factories exist.
  ///
  /// Not a general-purpose API: it skips the challenge/state handling every
  /// real caller does first, which is exactly why it is only for tests.
  @visibleForTesting
  Future<oauth_claims.OAuthIdentity> resolveIdentityFromTokens({
    required OAuthProvider provider,
    String? idToken,
    String? accessToken,
    String? expectedNonce,
  }) async {
    return await _identityFromTokens(
      provider: provider,
      idToken: idToken,
      accessToken: accessToken,
      expectedNonce: expectedNonce,
    );
  }

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
        case CompleteOAuthAuthPayload():
          throw ArgumentError(
            'Call completeOAuth instead of confirmAuth to complete an OAuth flow',
          );
      }
    });
  }

  Future<_AuthResult?> authenticateAdmin(AuthPayload payload) async {
    return await _run(() => _authenticateAdmin(payload));
  }

  Future<String> adminPasswordTable() async {
    return await _run(() => _adminCollectionFor(.password));
  }

  /// The `AsAdmin` collection configured for `AuthType.oauth`, resolved the
  /// same way [adminPasswordTable] resolves the password one.
  ///
  /// The dashboard sign-in screen needs this to tell an admin-table provider
  /// apart from an app-table one: `ZonaiDb.oauthProviders` answers for
  /// *every* `OAuth`-enabled table, and only the admin table's providers can
  /// begin an admin sign-in.
  Future<String> adminOAuthTable() async {
    return await _run(() => _adminCollectionFor(.oauth));
  }

  /// The configured `AsAdmin` table and the auth types it actually
  /// supports -- unlike [adminPasswordTable]/[adminOAuthTable], this
  /// doesn't assume a particular sign-in method is configured. `admin add`
  /// (and its siblings that don't care about sign-in method) use this to
  /// decide what an admin account creation needs, e.g. whether a password
  /// is required.
  Future<(String table, List<AuthType> authTypes)> adminTable() async {
    return await _run(_adminTable);
  }

  Future<Map<String, Object?>> createAdmin({
    required String email,
    String? password,
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

  /// [actingAdmin] is the signed-in caller for a dashboard-driven removal --
  /// omit it for the trusted CLI path (`zonai db admin remove`), which has
  /// no caller to check for self-removal against. Always revokes the
  /// removed admin's sessions (design §3.4) and always refuses to remove the
  /// table's last admin, regardless of caller (design §4 item 6).
  Future<Map<String, Object?>> removeAdmin({
    required String email,
    Jwt? actingAdmin,
  }) async {
    return await _run(
      () => _removeAdmin(email: email, actingAdmin: actingAdmin),
    );
  }

  Future<List<Map<String, Object?>>> listAdmins() async {
    return await _run(() => _listAdmins());
  }

  /// Design §3.1: refuses when [jwt] isn't admin on the resolved `AsAdmin`
  /// table, when an admin already exists for [email], and resends (rather
  /// than duplicates) a still-live invite.
  Future<Map<String, Object?>> inviteAdmin({
    required String email,
    required String jwt,
  }) async {
    return await _run(() => _inviteAdmin(email: email, jwt: jwt));
  }

  /// The same invite as [inviteAdmin], issued from `zonai db admin invite`
  /// where there is no session to check and none is wanted — see
  /// [_inviteAdminFromCli] for why that is a separate entry point and not a
  /// nullable `jwt`.
  ///
  /// The pairing worth knowing: `admin add` creates an admin outright and is
  /// how the first one exists at all; this creates nothing until the invitee
  /// proves the address, so it is the one to reach for when the address
  /// belongs to someone else.
  Future<Map<String, Object?>> inviteAdminFromCli({
    required String email,
  }) async {
    return await _run(() => _inviteAdminFromCli(email: email));
  }

  /// Design §3.4: sets `canConsume = false` on the live invite for [email],
  /// if any -- the link stops working.
  Future<void> revokeAdminInvite({
    required String email,
    required String jwt,
  }) async {
    return await _run(() => _revokeAdminInvite(email: email, jwt: jwt));
  }

  /// Pending invites for the resolved `AsAdmin` table: unconsumed and
  /// unexpired, never the secret hash.
  Future<List<Map<String, Object?>>> listAdminInvites({
    required String jwt,
  }) async {
    return await _run(() => _listAdminInvites(jwt: jwt));
  }

  /// [listAdminInvites] from `zonai db admin invites`, with no session to
  /// check — see [inviteAdminFromCli].
  Future<List<Map<String, Object?>>> listAdminInvitesFromCli() async {
    return await _run(_listAdminInvitesFromCli);
  }

  /// [revokeAdminInvite] from `zonai db admin revoke-invite`, with no
  /// session to check — see [inviteAdminFromCli].
  Future<void> revokeAdminInviteFromCli({required String email}) async {
    return await _run(() => _revokeAdminInviteFromCli(email: email));
  }

  /// Describes the invite [token] names **without consuming it**, or null
  /// when it names none that can still be used (design §7).
  ///
  /// The liveness probe the acceptance screen asks before it offers anything:
  /// [startAdminInviteOAuth] is the only other thing that can judge a token,
  /// and by the time it answers the browser has already left the dashboard.
  ///
  /// Unauthenticated on purpose — the invitee has no session, and the token
  /// is the authorization.
  ///
  /// Null covers expired, revoked, spent, forged and truncated alike, and
  /// telling them apart is not an omission to be fixed later: a probe that
  /// distinguished "expired" from "no such invite" would answer, for any
  /// address someone cared to try, whether that address has an invite
  /// pending. See [_describeAdminInvite].
  Future<AdminInviteDescription?> describeAdminInvite({
    required String token,
  }) async {
    return await _run(() => _describeAdminInvite(token: token));
  }

  /// Design §3.3: accepts the invite [token] names directly — creating the
  /// admin row, consuming the invite and returning a session — for admin
  /// tables that sign in with a password, an OTP or a magic link.
  ///
  /// [password] is required exactly when the invite's table declares
  /// `PasswordAuth`, and refused otherwise; [describeAdminInvite] is how the
  /// acceptance screen knows which before asking.
  ///
  /// Not a second way onto an OAuth-only table. Possession of the token
  /// proves control of the invited mailbox and nothing more, where
  /// [startAdminInviteOAuth]'s path additionally has a provider vouch that
  /// the identity signing in owns that address — so this refuses a table
  /// that declares OAuth alone rather than offering it a weaker door.
  Future<_AuthResult> acceptAdminInvite({
    required String token,
    String? password,
    Map<String, dynamic>? object,
  }) async {
    return await _run(
      () =>
          _acceptAdminInvite(token: token, password: password, object: object),
    );
  }

  /// Design §3.2 step 3: [startAdminOAuth]'s invite-bound counterpart --
  /// mints the same `oauthState` challenge but carries [inviteToken] in its
  /// metadata, so [completeOAuth] knows to attempt invite-bound provisioning
  /// (the one path an `isAdmin` callback is allowed to provision) instead of
  /// refusing outright.
  Future<String> startAdminInviteOAuth({
    required String inviteToken,
    required StartOAuthAuthPayload payload,
  }) async {
    return await _run(
      () => _startAdminInviteOAuth(inviteToken: inviteToken, payload: payload),
    );
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

  /// Every `(table, OAuthProviderPublic)` pair across every `OAuth`-enabled
  /// table -- what the dashboard and Dart client list sign-in buttons from.
  Future<List<OAuthProviderPublic>> oauthProviders() async {
    return await _run(_oauthProviders);
  }

  /// §3.1 step 1: mints the `oauthState` challenge and returns the
  /// authorization URL to redirect the user to.
  Future<String> startOAuth(String table, StartOAuthAuthPayload payload) async {
    return await _run(() => _startOAuth(table, payload));
  }

  /// Admin-dashboard counterpart of [startOAuth]: resolves the `AsAdmin`
  /// table configured for `AuthType.oauth` the same way
  /// [sendAdminResetPassword] resolves one for password reset, and flags the
  /// minted challenge so its callback never auto-provisions a new admin.
  Future<String> startAdminOAuth(StartOAuthAuthPayload payload) async {
    return await _run(() async {
      final table = await _adminCollectionFor(.oauth);
      return await _startOAuth(table, payload, isAdmin: true);
    });
  }

  /// Ends a flow the provider rejected and returns the `redirect_to` recorded
  /// at start, or `null` if no consumable challenge matches [state].
  Future<String?> abandonOAuth(String state) async {
    return await _run(() => _abandonOAuth(state));
  }

  /// §3.1 step 2: consumes the challenge, exchanges the code, resolves
  /// identity, and mints the session.
  Future<_OAuthCallbackResult> completeOAuth(
    CompleteOAuthAuthPayload payload,
  ) async {
    return await _run(() => _completeOAuthCallback(payload));
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
            () => ConfigResolver(mailman: _config),
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
            () => ConfigResolver(mailman: _config),
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
