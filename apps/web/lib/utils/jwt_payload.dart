import 'dart:convert';

/// Display info extracted from a signed-in user's JWT payload.
final class SessionUser {
  const SessionUser({
    required this.label,
    this.email,
    this.isAdmin = false,
    this.canEdit = false,
  });

  final String label;
  final String? email;
  final bool isAdmin;
  final bool canEdit;

  String get initial {
    final source = email ?? label;
    if (source.isEmpty) return '?';
    return source[0].toUpperCase();
  }
}

/// Base64url-decodes the middle segment of a JWT (no signature verification).
Map<String, Object?>? decodeJwtPayload(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;

  try {
    final decoded = jsonDecode(utf8.decode(_decodeBase64Url(parts[1])));
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  } on Object {
    return null;
  }
}

/// Reads user-facing fields from a JWT payload for the sidebar profile.
SessionUser? sessionUserFromToken(String token) {
  final payload = decodeJwtPayload(token);
  if (payload == null) return null;

  final user = payload['user'];
  String? email;
  if (user is Map) {
    final raw = user['email'];
    if (raw is String && raw.isNotEmpty) {
      email = raw;
    }
  }

  final userId = payload['userId'];
  final label = email ?? (userId is String && userId.isNotEmpty ? userId : 'Signed in');

  var isAdmin = false;
  var canEdit = false;
  final admin = payload['admin'];
  if (admin is Map) {
    if (admin['isAdmin'] == true) {
      isAdmin = true;
    }
    if (admin['canEdit'] == true) {
      canEdit = true;
    }
  }

  return SessionUser(label: label, email: email, isAdmin: isAdmin, canEdit: canEdit);
}

List<int> _decodeBase64Url(String segment) {
  var normalized = segment.replaceAll('-', '+').replaceAll('_', '/');
  switch (normalized.length % 4) {
    case 2:
      normalized += '==';
    case 3:
      normalized += '=';
    default:
      break;
  }
  return base64.decode(normalized);
}
