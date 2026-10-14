import 'dart:convert';

import 'package:revali_core/revali_core.dart' show HttpError;
import 'package:zonai_schema/src/exceptions/hook_refused_exception.dart';
import 'package:zonai_schema/src/exceptions/sign_up_declined_exception.dart';

/// The app's deliberate refusals, carried from a worker to the host as data.
///
/// Only a string used to cross the worker boundary on failure, so a typed
/// refusal had to be written into the error text and parsed back out. Caller
/// data can end up in that text (a crash message that quotes a field), so a
/// parse could be fooled into reading a crash as a refusal. Instead the worker
/// puts [encodeWorkerRefusal]'s map on `MessageErrorResponse.refusal`, and
/// only for the two types below, so a refusal is never read out of free text.
///
/// [encodeWorkerRefusal] and [decodeWorkerRefusal] are one protocol, kept in
/// one file, and `worker_refusal_test.dart` round-trips them.

/// The field for [error], or `null` when it is not a refusal and must reach
/// the host as an ordinary failure.
Map<String, Object?>? encodeWorkerRefusal(Object error) {
  return switch (error) {
    HookRefusedException(:final error)
        when HookRefusedException.refuses(error) =>
      {
        'type': _hookRefused,
        'statusCode': error.statusCode,
        'code': error.code,
        'message': error.message,
        if (error.details.isNotEmpty) 'details': _jsonSafe(error.details),
      },
    SignUpDeclinedException(:final reason) => {
      'type': _signUpDeclined,
      'reason': reason,
    },
    _ => null,
  };
}

/// The refusal [refusal] describes, or `null` when it is absent or not one
/// the host knows. A hook refusal outside 4xx is not a refusal.
Exception? decodeWorkerRefusal(Map<String, Object?>? refusal) {
  switch (refusal) {
    case {
      'type': _hookRefused,
      'statusCode': final int statusCode,
      'code': final String code,
      'message': final String message,
    }:
      final error = HttpError(
        statusCode: statusCode,
        code: code,
        message: message,
        details: switch (refusal['details']) {
          final Map<String, Object?> details => details,
          _ => const {},
        },
      );
      return HookRefusedException.refuses(error)
          ? HookRefusedException(error)
          : null;
    case {'type': _signUpDeclined, 'reason': final String reason}:
      return SignUpDeclinedException(reason);
  }
  return null;
}

/// `details` is meant to be JSON already, since it goes to the client. A value
/// that is not degrades to its text rather than failing the reply.
Map<String, Object?> _jsonSafe(Map<String, Object?> details) =>
    (jsonDecode(jsonEncode(details, toEncodable: (o) => '$o')) as Map)
        .cast<String, Object?>();

const _hookRefused = 'hookRefused';
const _signUpDeclined = 'signUpDeclined';
