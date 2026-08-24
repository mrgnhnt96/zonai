import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/exceptions/schema_exception.dart';
import 'package:zonai_schema/src/exceptions/sign_up_declined_exception.dart';
import 'package:zonai_server/src/exceptions/oauth_http_exception.dart';

import 'package:zonai_server/src/handlers/email_handler.dart';

import '../controllers/root_controller.dart';

/// What a client is told when the real reason is none of its business.
///
/// Every branch that used to interpolate an exception into the body handed the
/// caller something it could not otherwise see: `_dashboard` and `_cron_jobs`
/// are internal table names, and the messages echo back the action and table
/// that were probed. That turns any endpoint into an oracle -- vary the table
/// name, watch "table is not registered" (404) turn into "access denied"
/// (403), and the schema can be enumerated without ever being authorised.
///
/// The detail is not lost, it moves: [_serverSide] logs it against the
/// request's `x-trace-id`, so an operator reads the cause out of the logs by
/// correlating the id the client was already given.
const _forbidden = 'Forbidden';
const _notFound = 'Not found';

final class Exceptions implements LifecycleComponent {
  const Exceptions();

  /// Records the real cause where operators can reach it.
  ///
  /// `Trace` puts an `x-trace-id` on every response and logs through a
  /// callback that persists to the log table, so logging here is what makes a
  /// generic client-facing body diagnosable rather than merely quiet.
  /// Resolved with an `orElse` rather than through the bare `logger` getter:
  /// that getter throws when no logger is in scope, and an exception *catcher*
  /// that throws converts a deliberate 403 into a 500 -- turning the fix into
  /// a worse leak than the one it replaced.
  static void _serverSide(Object exception) {
    final log = read(loggerProvider, orElse: () => Logger.print(level: .info));
    log.warn('Suppressed detail in client response: $exception');
  }

  ExceptionCatcherResult<SchemaEndpointNotFoundException> onSchemaEndpoint(
    SchemaEndpointNotFoundException exception,
  ) {
    return .handled(statusCode: 404, body: {'error': _notFound});
  }

  ExceptionCatcherResult<EmailForbiddenException> onEmailForbidden(
    EmailForbiddenException exception,
  ) {
    return .handled(statusCode: 403, body: {'error': _forbidden});
  }

  ExceptionCatcherResult<EmailRateLimitException> onEmailRateLimit(
    EmailRateLimitException exception,
  ) {
    return .handled(statusCode: 429, body: {'error': 'Rate limit exceeded'});
  }

  ExceptionCatcherResult<ExecutableUnavailableException>
  onExecutableUnavailable(ExecutableUnavailableException exception) {
    return .handled(statusCode: 503, body: {'error': exception.error});
  }

  ExceptionCatcherResult<WorkerProcessFailedException> onWorkerFailed(
    WorkerProcessFailedException exception,
  ) {
    return .handled(statusCode: 503, body: {'error': '$exception'});
  }

  ExceptionCatcherResult<WriteBackpressureException> onWriteBackpressure(
    WriteBackpressureException exception,
  ) {
    return .handled(statusCode: 503, body: {'error': '$exception'});
  }

  /// A sign-up the app refused from its own `beforeSignUp` hook.
  ///
  /// The reason IS rendered to the caller, unlike the `_forbidden` branches
  /// above, and that is the point rather than an oversight: the app chose
  /// this string for the person who typed the address ("invite only", "that
  /// domain is not eligible"), and a bare "Forbidden" would make the hook
  /// useless for the thing it exists to do. The oracle concern those
  /// branches guard against does not apply -- nothing here is derived from
  /// the schema, and the app is free to return a constant.
  ///
  /// 403, not 400: the request is well-formed and the server understood it.
  ExceptionCatcherResult<SignUpDeclinedException> onSignUpDeclined(
    SignUpDeclinedException exception,
  ) {
    return .handled(statusCode: 403, body: {'error': exception.reason});
  }

  ExceptionCatcherResult<AuthException> onAuthException(
    AuthException exception,
  ) {
    return switch (exception) {
      InvalidJwtException() ||
      JwtRecordNotFoundException() ||
      UserNotFoundAuthException() ||
      EmailNotFoundAuthException() ||
      InvalidPasswordOrEmailException() ||
      InvalidOrExpiredCodeException() ||
      CodeExpiredException() ||
      InvalidOrExpiredResetPasswordLinkException() ||
      ResetPasswordLinkExpiredException() ||
      InvalidOrExpiredVerifyEmailLinkException() ||
      VerifyEmailLinkExpiredException() => .handled(
        statusCode: 401,
        body: {'error': '$exception'},
      ),
      // 403, not 401. The whole sign-in oracle contract (docs/auth.md,
      // "Failed sign-in") rests on 401 meaning *these credentials are not
      // valid*, rendered identically for a wrong password and an unknown
      // address. This says the opposite -- the password was right -- so it
      // must not share that status. 409 was considered on the
      // AdminInviteRequiresOAuthException precedent ("wrong door") and
      // rejected: this caller is at the right door and is being refused.
      //
      // Not a 200 carrying no accessToken either: every client written before
      // this existed would read that as success, proceed with a null token,
      // and fail somewhere further away. A 4xx fails closed.
      //
      // The body is the ONE structured envelope zonai emits -- every other
      // error here is a bare sentence. That is deliberate and narrow: a
      // sentence cannot carry a ticket and cannot be branched on, and
      // migrating the rest is a breaking wire change that gets its own
      // commit and its own migration note (design §5.2, option (a)).
      // Built through HttpError so the shape cannot drift from the one
      // ServerException.fromBody already parses on the client.
      //
      // `token` is read explicitly here. Nothing interpolates the exception
      // -- see the invariant on PasswordResetRequiredException.
      final PasswordResetRequiredException e => .handled(
        statusCode: 403,
        body: HttpError.forbidden(
          code: 'password_reset_required',
          message: 'This account must set a new password before signing in',
          details: {
            'resetToken': e.token,
            'expiresIn': e.expiresIn.inSeconds,
            'reason': e.reason.name,
          },
        ).toEnvelope(),
      ),
      AlreadyAuthenticatedException() => .handled(
        statusCode: 409,
        body: {'error': '$exception'},
      ),
      PasswordReuseException() => .handled(
        statusCode: 422,
        body: {'error': '$exception'},
      ),
      AuthRateLimitException() => .handled(
        statusCode: 429,
        body: {'error': '$exception'},
      ),
      AuthEmailForbiddenException() => .handled(
        statusCode: 403,
        body: {'error': '$exception'},
      ),
      AuthTableNotFoundException() ||
      AuthFailedException() => _internal(exception),
      ExternalIdpProvisioningRejectedException() => .handled(
        statusCode: 403,
        body: {'error': '$exception'},
      ),
      OAuthProviderNotFoundException() => .handled(
        statusCode: 404,
        body: {'error': '$exception'},
      ),
      OAuthRedirectNotAllowedException() => .handled(
        statusCode: 400,
        body: {'error': '$exception'},
      ),
      AdminInviteEmailMismatchException() => .handled(
        statusCode: 403,
        body: {'error': '$exception'},
      ),
      // Not 403: the invite is valid and the caller is not forbidden from
      // accepting it -- they are at the wrong door. 409 is the same "your
      // request conflicts with how this resource works" the OAuth-only table
      // is stating, and the message names the route that does work.
      AdminInviteRequiresOAuthException() => .handled(
        statusCode: 409,
        body: {'error': '$exception'},
      ),
      // 400 rather than 422: a password sent to a table that takes none (or
      // omitted from one that requires it) is a malformed request for this
      // endpoint, not a well-formed one carrying an unprocessable value.
      AdminInvitePasswordMismatchException() => .handled(
        statusCode: 400,
        body: {'error': '$exception'},
      ),
      CannotRemoveSelfAsAdminException() => .handled(
        statusCode: 403,
        body: {'error': '$exception'},
      ),
      LastAdminCannotBeRemovedException() => .handled(
        statusCode: 409,
        body: {'error': '$exception'},
      ),
    };
  }

  /// Both members are malformed-callback shapes decided before anything is
  /// consumed or exchanged, so both are 400. Their `toString`s carry only
  /// the provider id and, for the incomplete case, *which* field was absent
  /// — never a `code` or a `state` (design §4 item 7).
  ExceptionCatcherResult<OAuthHttpException> onOAuthHttpException(
    OAuthHttpException exception,
  ) {
    return switch (exception) {
      OAuthProviderRejectedException() || OAuthCallbackIncompleteException() =>
        .handled(statusCode: 400, body: {'error': '$exception'}),
    };
  }

  ExceptionCatcherResult<CrudException> onCrudException(
    CrudException exception,
  ) {
    return switch (exception) {
      RecordNotFoundException() || RecordDeletedWhileStreamingException() =>
        .handled(statusCode: 404, body: {'error': '$exception'}),
      PasswordUpdateForbiddenException() => .handled(
        statusCode: 403,
        body: {'error': '$exception'},
      ),
      InvalidPasswordUpdateException() => .handled(
        statusCode: 422,
        body: {'error': '$exception'},
      ),
      ForeignKeyConstraintException() => .handled(
        statusCode: 422,
        body: {'error': '$exception'},
      ),
      UniqueConstraintException() => .handled(
        statusCode: 409,
        body: {'error': '$exception'},
      ),
      InvalidColumnValueException() => .handled(
        statusCode: 422,
        body: {'error': '$exception'},
      ),
      RecordCreateFailedException() ||
      RecordReadFailedException() ||
      RecordUpdateFailedException() ||
      RecordDeleteFailedException() ||
      RecordListFailedException() ||
      RecordCountFailedException() => _internal(exception),
    };
  }

  ExceptionCatcherResult<PhotoException> onPhotoException(
    PhotoException exception,
  ) {
    return switch (exception) {
      InvalidPhotoIdException() || InvalidPhotoPathException() => .handled(
        statusCode: 400,
        body: {'error': '$exception'},
      ),
      PhotoNotFoundException() || PhotoFileNotFoundException() => .handled(
        statusCode: 404,
        body: {'error': '$exception'},
      ),
      PhotoFileAlreadyExistsException() => .handled(
        statusCode: 409,
        body: {'error': '$exception'},
      ),
      PhotoContentTypeNotAllowedException() => .handled(
        statusCode: 415,
        body: {'error': '$exception'},
      ),
      PhotosTableNotFoundException() ||
      PhotoInsertFailedException() ||
      PhotoImageTypeUndetectableException() => _internal(exception),
    };
  }

  ExceptionCatcherResult<SchemaException> onSchemaException(
    SchemaException exception,
  ) {
    return switch (exception) {
      ColumnNotExpandableException() => .handled(
        statusCode: 400,
        body: {'error': '$exception'},
      ),
      ColumnNotFoundException() => .handled(
        statusCode: 400,
        body: {'error': '$exception'},
      ),
      // Generic, and identical to what a denied table returns, so that
      // "this table does not exist" and "you may not touch this table" are
      // indistinguishable from outside. Naming the table here was the other
      // half of the enumeration oracle.
      TableNotRegisteredException() => _suppressed(
        exception,
        statusCode: 404,
        error: _notFound,
      ),
      CustomOperationRequiresWhereException() => .handled(
        statusCode: 400,
        body: {'error': '$exception'},
      ),
      // All 400: each names something wrong with the *request* -- a filter on
      // a column that may not be filtered, an operation named after a classic
      // verb, an operation the table does not implement. Reporting the message
      // is safe here for the same reason it is for the cases above: each one
      // describes schema shape or the caller's own input, never row data. A
      // secret column's name is not a secret; its value is, and that is what
      // refusing the filter protects.
      SecretColumnFilterException() ||
      CustomOperationNameCollisionException() ||
      CustomOperationNotImplementedException() => .handled(
        statusCode: 400,
        body: {'error': '$exception'},
      ),
      DatabaseNotOpenException() => .handled(
        statusCode: 503,
        body: {'error': '$exception'},
      ),
      // 400, not 500: every case of this is the app pointing `push` at a
      // collection or column that cannot be a recipient set. Reporting the
      // message is the point -- "not a deviceToken column" tells an author
      // exactly what to change, and "Internal server error" tells them
      // nothing. The message names only schema shape, never row data.
      PushTargetException() => .handled(
        statusCode: 400,
        body: {'error': '$exception'},
      ),
      ExpandedRecordReadFailedException() || StaleRowRulesRequestException() =>
        .handled(statusCode: 500, body: {'error': 'Internal server error'}),
    };
  }

  /// An API token offered somewhere it is not a credential.
  ///
  /// Without this the sealed family had no catcher at all, and every one of
  /// them reached revali's default handler as an unhandled exception: a token
  /// presented to `/admin/**` or `/dashboard/maintenance/**` -- the
  /// default-deny working exactly as designed -- answered **500 Internal
  /// Server Error**. Found by `test/e2e/api_token_http_e2e_test.dart`; a
  /// refusal that reads as a server fault is one nobody debugs as a refusal.
  ///
  /// 401 rather than 403: the caller is not authenticated *here*, whatever it
  /// is elsewhere, which is the same answer `InvalidJwtException` gets. The
  /// message is a constant and names no table, so echoing it leaks nothing --
  /// and it is the one line that tells an integration author what happened.
  ///
  /// The other two members are CLI-side today (`zonai db token create` /
  /// `revoke`) and reach no route; they are mapped anyway so that adding a
  /// mint endpoint later cannot reintroduce the 500.
  ExceptionCatcherResult<ApiTokenException> onApiTokenException(
    ApiTokenException exception,
  ) {
    return switch (exception) {
      ApiTokenNotAcceptedHereException() => .handled(
        statusCode: 401,
        body: {'error': '$exception'},
      ),
      InvalidApiTokenScopeException() => _suppressed(
        exception,
        statusCode: 400,
        error: '$exception',
      ),
      ApiTokenNotFoundException() => _suppressed(
        exception,
        statusCode: 404,
        error: _notFound,
      ),
    };
  }

  /// Both permission failures answer identically, and neither names the table.
  ///
  /// `TableAccessDeniedException` and `RowAccessDeniedException` stringify to
  /// `Access denied: action "<op>" on table "<table>"` -- the probe echoed
  /// back. Telling the two apart also leaks whether a *row* matched, which is
  /// an existence check on data the caller was just refused.
  ExceptionCatcherResult<PermissionException> onPermissionException(
    PermissionException exception,
  ) {
    _serverSide(exception);
    return .handled(statusCode: 403, body: {'error': _forbidden});
  }

  ExceptionCatcherResult<T> _internal<T extends Exception>(T e) {
    return .handled(statusCode: 500, body: {'error': 'Internal server error'});
  }

  /// Answers with [error] and logs the real [exception] for operators.
  ExceptionCatcherResult<T> _suppressed<T extends Exception>(
    T exception, {
    required int statusCode,
    required String error,
  }) {
    _serverSide(exception);
    return .handled(statusCode: statusCode, body: {'error': error});
  }
}
