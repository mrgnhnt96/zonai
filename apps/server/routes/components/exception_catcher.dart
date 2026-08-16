import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_schema/src/exceptions/schema_exception.dart';

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
    final log = read(
      loggerProvider,
      orElse: () => Logger.print(level: .info),
    );
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
