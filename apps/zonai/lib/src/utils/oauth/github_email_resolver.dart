import 'dart:convert';

import 'package:http/http.dart' as http;

import 'oauth_exception.dart';

/// Resolves GitHub's primary verified email via `GET /user/emails`, for the
/// case `GET /user` returns `email: null` (a private/unset primary email —
/// design §2.3, §3.3).
///
/// Only an email that is both `primary: true` and `verified: true` is
/// returned — an unverified address must never be treated as verified,
/// since `OAuthLinking.byVerifiedEmail` linking depends on that distinction
/// (design §4.6).
final class GitHubEmailResolver {
  GitHubEmailResolver({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static final _emailsEndpoint = Uri.parse(
    'https://api.github.com/user/emails',
  );

  /// Returns the primary verified email for [accessToken]'s user, or null
  /// if none of the account's emails are both primary and verified.
  Future<String?> primaryVerifiedEmail(String accessToken) async {
    final http.Response response;
    try {
      response = await _httpClient.get(
        _emailsEndpoint,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/vnd.github+json',
        },
      );
    } on Object catch (e) {
      throw OAuthResponseException('GitHub /user/emails request failed: $e');
    }
    if (response.statusCode != 200) {
      throw OAuthResponseException(
        'GitHub /user/emails returned status ${response.statusCode}',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on Object {
      throw const OAuthResponseException(
        'GitHub /user/emails returned a non-JSON body',
      );
    }
    if (decoded is! List) {
      throw const OAuthResponseException(
        'GitHub /user/emails returned a non-array body',
      );
    }

    for (final entry in decoded) {
      if (entry is! Map) continue;
      final email = entry['email'];
      final isPrimary = entry['primary'] == true;
      final isVerified = entry['verified'] == true;
      if (email is String && isPrimary && isVerified) {
        return email;
      }
    }
    return null;
  }
}
