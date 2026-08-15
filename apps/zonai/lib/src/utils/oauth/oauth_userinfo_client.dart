import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:zonai_schema/src/types/oauth/oauth_provider.dart';
import 'package:zonai_schema/src/types/oauth/oauth_provider_kind.dart';

import 'oauth_exception.dart';

/// Fetches [OAuthEndpoints.userInfo] with [accessToken] and returns the
/// decoded claims map, for providers whose identity comes from userinfo
/// rather than (or in addition to) an `id_token`.
///
/// **Runtime finding, not reflected in `docs/oauth-design.md` §2.3:**
/// Facebook's Graph API `/me` returns only `name` (and `id`) unless the
/// request explicitly lists the fields it wants via a `fields` query
/// parameter — confirmed against Meta's Graph API user reference, which
/// marks every other field (including `email` and `picture`) as
/// non-default. Calling it the way [OAuthEndpoints.userInfo] is written —
/// a bare URL — would silently return an identity with no email, which
/// `OAuthLinking.byVerifiedEmail` would then never be able to link or even
/// notice is missing. This client appends `fields=id,name,email,picture`
/// for [OAuthProviderKind.facebook] specifically; every other provider's
/// userinfo endpoint returns its full documented claim set by default.
final class OAuthUserInfoClient {
  OAuthUserInfoClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const _facebookFields = 'id,name,email,picture';

  Future<Map<String, Object?>> fetch({
    required OAuthProvider provider,
    required String accessToken,
  }) async {
    final endpoint = provider.endpoints.userInfo;
    if (endpoint == null) {
      throw const OAuthIdentityUnresolvedException(
        'provider has no userInfo endpoint',
      );
    }

    final http.Response response;
    try {
      response = await _httpClient.get(
        _requestUri(provider, endpoint),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
    } on Object catch (e) {
      throw OAuthResponseException('userinfo request failed: $e');
    }
    if (response.statusCode != 200) {
      throw OAuthResponseException(
        'userinfo endpoint returned status ${response.statusCode}',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on Object {
      throw const OAuthResponseException(
        'userinfo endpoint returned a non-JSON body',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const OAuthResponseException(
        'userinfo endpoint returned a non-object body',
      );
    }
    return decoded;
  }

  Uri _requestUri(OAuthProvider provider, String endpoint) {
    final uri = Uri.parse(endpoint);
    if (provider case BuiltInOAuthProvider(kind: OAuthProviderKind.facebook)) {
      return uri.replace(
        queryParameters: {...uri.queryParameters, 'fields': _facebookFields},
      );
    }
    return uri;
  }
}
