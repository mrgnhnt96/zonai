import 'package:zonai_schema/src/types/oauth/oauth_claim_map.dart';

import 'oauth_exception.dart';

/// The normalized shape every provider's claims/userinfo payload is reduced
/// to via [OAuthClaimMap], regardless of how deeply each field is nested in
/// the provider's own response shape.
final class OAuthIdentity {
  const OAuthIdentity({
    required this.subject,
    this.email,
    this.emailVerified,
    this.name,
    this.picture,
  });

  final String subject;
  final String? email;

  /// Null when the provider's [OAuthClaimMap.emailVerified] path is unset
  /// (the provider never asserts this) or the claim wasn't present —
  /// callers must not treat null as verified.
  final bool? emailVerified;

  final String? name;
  final String? picture;
}

/// Extracts an [OAuthIdentity] from [source] (decoded `id_token` claims or a
/// userinfo response body) using [claims]'s field paths. Paths are dotted
/// for nested fields, e.g. Facebook's `'picture.data.url'`.
///
/// Throws [OAuthIdentityUnresolvedException] when the `subject` path doesn't
/// resolve to a non-empty string — every other field is optional because
/// providers vary in what they assert (design §2.3 built-in factory docs).
///
/// **Runtime finding, not reflected in `docs/oauth-design.md` §2.3:**
/// GitHub's `GET /user` documents `id` as a JSON *number*
/// (`"id": integer, format: int64`), not a string — but every other
/// built-in provider's subject claim (`sub`, or Facebook/Discord's `id`) is
/// a string. A subject extractor that only accepted strings would throw
/// [OAuthIdentityUnresolvedException] on every GitHub sign-in. Subject
/// extraction below coerces a numeric subject to its decimal string form;
/// every other field stays string-only, since a provider returning a
/// number for `email`/`name`/`picture` would be a genuine anomaly, not a
/// documented shape.
OAuthIdentity extractOAuthIdentity(
  OAuthClaimMap claims,
  Map<String, Object?> source,
) {
  final subject = _subjectAt(source, claims.subject);
  if (subject == null || subject.isEmpty) {
    throw OAuthIdentityUnresolvedException(
      'subject path "${claims.subject}" did not resolve to a non-empty '
      'string',
    );
  }
  return OAuthIdentity(
    subject: subject,
    email: _stringAt(source, claims.email),
    emailVerified: claims.emailVerified == null
        ? null
        : _boolAt(source, claims.emailVerified!),
    name: claims.name == null ? null : _stringAt(source, claims.name!),
    picture: claims.picture == null ? null : _stringAt(source, claims.picture!),
  );
}

String? _stringAt(Map<String, Object?> source, String path) {
  final value = _walkClaimPath(source, path);
  return value is String ? value : null;
}

/// Like [_stringAt], but also accepts a JSON number (GitHub's integer `id`)
/// and stringifies it in decimal form.
String? _subjectAt(Map<String, Object?> source, String path) {
  return switch (_walkClaimPath(source, path)) {
    String s => s,
    num n => n.toInt().toString(),
    _ => null,
  };
}

bool? _boolAt(Map<String, Object?> source, String path) {
  return switch (_walkClaimPath(source, path)) {
    bool b => b,
    String s => s.toLowerCase() == 'true',
    _ => null,
  };
}

Object? _walkClaimPath(Map<String, Object?> root, String dottedPath) {
  Object? current = root;
  for (final segment in dottedPath.split('.')) {
    if (current is! Map<String, Object?>) return null;
    current = current[segment];
  }
  return current;
}
