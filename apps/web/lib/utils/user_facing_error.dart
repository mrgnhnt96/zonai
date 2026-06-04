import 'dart:convert';

import 'package:revali_client/revali_client.dart';

/// Turns exceptions from API/DB calls into short toast copy.
String userFacingError(Object error) {
  final text = switch (error) {
    StateError(:final message) => message,
    ServerException(:final body?) when body.isNotEmpty => _errorFromHttpBody(body) ?? error.message,
    ServerException(:final message) => message,
    FormatException(:final message) => message,
    _ => error.toString(),
  };
  return _normalizeErrorMessage(text);
}

String? _errorFromHttpBody(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['error'] != null) {
      return decoded['error'].toString();
    }
  } on Object {
    // Fall through to raw body.
  }
  final trimmed = body.trim();
  return trimmed.length <= 500 ? trimmed : null;
}

String _normalizeErrorMessage(String message) {
  var text = message.trim();

  const updatePrefix = 'Failed to update row: ';
  if (text.startsWith(updatePrefix)) {
    text = text.substring(updatePrefix.length).trim();
  }

  const deletePrefix = 'Failed to delete rows: ';
  if (text.startsWith(deletePrefix)) {
    text = text.substring(deletePrefix.length).trim();
  }

  const dbPrefix = 'Failed to run database operation: ';
  if (text.startsWith(dbPrefix)) {
    text = text.substring(dbPrefix.length).trim();
  }

  const badStatePrefix = 'Bad state: ';
  if (text.startsWith(badStatePrefix)) {
    text = text.substring(badStatePrefix.length).trim();
  }

  if (text.contains('Invalid radix-10 number')) {
    return 'An ID field has an invalid format. Use the full text ID (for example test-1234567890_co).';
  }

  final lower = text.toLowerCase();
  if (lower.contains('foreign key constraint failed') || lower.contains('foreign key')) {
    return 'That reference does not match an existing row.';
  }

  return text;
}
