import 'dart:convert';

import 'package:revali_core/revali_core.dart' show HttpError;

/// A `beforeCreate`, `beforeUpdate` or `beforeDelete` hook's deliberate
/// refusal, on its way from the extensions worker to the host.
///
/// A hook refuses by throwing an [HttpError] with a 4xx status. The worker
/// wraps it in this (`DbExtensions` does, around those three hooks only), and
/// the host unwraps it and rethrows the [error], which the server answers with
/// its status and envelope. Any other throw, an [HttpError] outside 4xx
/// included, is a server error and stays one.
///
/// ## Why this class carries its own parser
///
/// The same reason `SignUpDeclinedException` does. Only a string crosses the
/// worker boundary on failure (`MessageErrorResponse`), so the host gets
/// `toString()` and nothing else. [toString] writes [_marker] and the fields as
/// JSON, and [tryParse] reads them back. Keeping the pair in one file makes a
/// change to the format one edit, and `hook_refused_exception_test.dart`
/// round-trips it.
///
/// In-process extensions never serialize, and arrive as the real object. The
/// host handles both in `_runExtension`.
final class HookRefusedException implements Exception {
  const HookRefusedException(this.error);

  /// Whether [error] is a refusal, rather than a failure: a 4xx.
  static bool refuses(HttpError error) =>
      error.statusCode >= 400 && error.statusCode < 500;

  /// Recovers a [HookRefusedException] from the text an extension worker sent
  /// back, or `null` when [message] describes some other failure.
  ///
  /// Not anchored to the start, because the worker wraps the cause in its own
  /// framing (`Error handling request: <cause>`). Anything after the marker
  /// that is not the expected JSON, or that names a status outside 4xx, is
  /// not a refusal.
  static HookRefusedException? tryParse(String message) {
    final at = message.indexOf(_marker);
    if (at < 0) return null;

    try {
      final json = jsonDecode(message.substring(at + _marker.length).trim());
      if (json case {
        'statusCode': final int statusCode,
        'code': final String code,
        'message': final String text,
      }) {
        final error = HttpError(
          statusCode: statusCode,
          code: code,
          message: text,
          details: switch (json['details']) {
            final Map<String, Object?> details => details,
            _ => const {},
          },
        );
        return refuses(error) ? HookRefusedException(error) : null;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  /// What the caller is answered with. Chosen by the app, and rendered to the
  /// client as is, so it must not carry anything the caller should not see.
  final HttpError error;

  /// The needle [tryParse] looks for. Changing it is a protocol change: a
  /// host and a worker built against different text answer a refusal with a
  /// 500.
  static const _marker = 'zonai:hook-refused: ';

  @override
  String toString() {
    final fields = {
      'statusCode': error.statusCode,
      'code': error.code,
      'message': error.message,
      if (error.details.isNotEmpty) 'details': error.details,
    };
    // `details` is meant to be JSON already, since it goes to the client. A
    // value that is not degrades to its text rather than failing the refusal.
    return '$_marker${jsonEncode(fields, toEncodable: (o) => '$o')}';
  }
}
