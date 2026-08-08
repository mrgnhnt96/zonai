import 'package:revali_router/revali_router.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_schema/src/exceptions/schema_exception.dart';

final class Exceptions implements LifecycleComponent {
  const Exceptions();

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
      TableNotRegisteredException() => .handled(
        statusCode: 404,
        body: {'error': '$exception'},
      ),
      DatabaseNotOpenException() => .handled(
        statusCode: 503,
        body: {'error': '$exception'},
      ),
      ExpandedRecordReadFailedException() ||
      StaleRowRulesRequestException() => .handled(
        statusCode: 500,
        body: {'error': 'Internal server error'},
      ),
    };
  }

  ExceptionCatcherResult<PermissionException> onPermissionException(
    PermissionException exception,
  ) {
    return .handled(statusCode: 403, body: {'error': '$exception'});
  }

  ExceptionCatcherResult<T> _internal<T extends Exception>(T e) {
    return .handled(statusCode: 500, body: {'error': 'Internal server error'});
  }
}
