import 'package:revali_client/revali_client.dart' show ServerException;

/// The server refused an update because a target row did not meet the update's
/// `expect`, and wrote nothing.
///
/// Distinct from a 404 on purpose: "the row changed under you" and "the row is
/// gone" call for opposite responses from a client that is reconciling. The
/// server answers `412` with code [code] and puts the failing rows -- as they
/// are now, and only those the caller may view -- in [current], so a client
/// can reconcile without a second read.
///
/// Translated from the raw [ServerException] `revali_client` throws for every
/// non-2xx, the same way `PasswordResetRequiredException` is.
class PreconditionFailedException implements Exception {
  const PreconditionFailedException({
    required this.current,
    required this.message,
  });

  /// Builds one from [exception] when it carries this error, and `null`
  /// otherwise. A 412 with any other `code` is somebody else's failure and
  /// keeps its own type.
  static PreconditionFailedException? tryFrom(ServerException exception) {
    if (exception.statusCode != 412 || exception.code != code) return null;

    final rows = exception.details?['current'];
    return PreconditionFailedException(
      current: [
        if (rows is List)
          for (final row in rows)
            if (row is Map) row.cast<String, Object?>(),
      ],
      message: exception.reason ?? exception.message,
    );
  }

  /// The server's stable identifier for this failure -- the thing to branch on.
  static const code = 'precondition_failed';

  /// Each target row that failed `expect`, as it is now. Empty when none of
  /// them is one the caller may view.
  final List<Map<String, Object?>> current;

  /// The server's human-readable explanation. Never parse it; branch on
  /// [code].
  final String message;

  @override
  String toString() =>
      'PreconditionFailedException: ${current.length} row(s) did not meet expect';
}

/// Re-throws a [ServerException] as a [PreconditionFailedException] when it is
/// one, and anything else unchanged.
Future<T> translatePreconditionRefusal<T>(Future<T> Function() request) async {
  try {
    return await request();
  } on ServerException catch (e) {
    throw PreconditionFailedException.tryFrom(e) ?? e;
  }
}
