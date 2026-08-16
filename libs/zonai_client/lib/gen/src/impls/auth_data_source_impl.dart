part of '../../client.dart';

class AuthDataSourceImpl implements AuthDataSource {
  const AuthDataSourceImpl({
    required RevaliClient client,
    required Storage storage,
  }) : _client = client,
       _storage = storage;

  final RevaliClient _client;

  final Storage _storage;

  @override
  Future<Map<String, Object?>?> authenticate({
    required AuthBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth',
      headers: {'authorization': authorization},
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map? data}) {
      return data?.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>?> refreshToken({
    required String authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/refresh',
      headers: {'authorization': authorization},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map? data}) {
      return data?.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<void> sendResetPassword({
    required ResetPasswordAuthBody body,
    String? authorization,
  }) async {
    await _client.request(
      method: 'POST',
      path: '/auth/reset-password',
      headers: {'authorization': authorization},
      body: body,
    );
  }

  @override
  Future<void> sendVerifyEmail({
    VerifyEmailAuthBody? body,
    required String authorization,
  }) async {
    await _client.request(
      method: 'POST',
      path: '/auth/verify-email',
      headers: {'authorization': authorization},
      body: body,
    );
  }

  @override
  Future<Map<String, Object?>?> confirm({required VerifyAuthBody body}) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/confirm',
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map? data}) {
      return data?.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>?> adminAuthenticate({
    required AdminAuthBody body,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/admin',
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map? data}) {
      return data?.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>> signIn({required SignInAuthBody body}) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/sign-in',
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>> signUp({
    required SignUpAuthBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/sign-up',
      headers: {'authorization': authorization},
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<void> oauthCallbackFormPost({
    required String provider,
    required OAuthCallbackBody body,
  }) async {
    await _client.request(
      method: 'POST',
      path: '/auth/oauth/callback/${provider}',
      body: body,
    );
  }

  @override
  Future<Map<String, Object?>> oauth({required OAuthBody body}) async {
    final response = await _client.request(
      method: 'POST',
      path: '/auth/oauth',
      body: body,
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<List<Map<String, Object?>>> oauthProviders({String? table}) async {
    final response = await _client.request(
      method: 'GET',
      path: '/auth/oauth/providers',
      query: {'table': table},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final List data}) {
      return data
          .map(
            (e) => (e as Map).map(
              (key, value) => MapEntry((key as String), value),
            ),
          )
          .toList();
    }

    throw Exception('Invalid response');
  }

  @override
  Future<void> startOAuth({
    required String provider,
    required String table,
    String? redirectTo,
    String? authorization,
  }) async {
    await _client.request(
      method: 'GET',
      path: '/auth/oauth/start/${provider}',
      headers: {'authorization': authorization},
      query: {'table': table, 'redirect_to': redirectTo},
    );
  }

  @override
  Future<void> startAdminOAuth({
    required String provider,
    String? redirectTo,
    String? authorization,
  }) async {
    await _client.request(
      method: 'GET',
      path: '/auth/admin/oauth/start/${provider}',
      headers: {'authorization': authorization},
      query: {'redirect_to': redirectTo},
    );
  }

  @override
  Future<Map<String, Object?>> adminInviteStatus({
    required String token,
  }) async {
    final response = await _client.request(
      method: 'GET',
      path: '/auth/admin/invite',
      query: {'token': token},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<void> startAdminInviteOAuth({
    required String provider,
    required String token,
    String? redirectTo,
  }) async {
    await _client.request(
      method: 'GET',
      path: '/auth/admin/invite/oauth/start/${provider}',
      query: {'token': token, 'redirect_to': redirectTo},
    );
  }

  @override
  Future<void> oauthCallback({
    required String provider,
    String? code,
    String? state,
    String? error,
  }) async {
    await _client.request(
      method: 'GET',
      path: '/auth/oauth/callback/${provider}',
      query: {'code': code, 'state': state, 'error': error},
    );
  }

  @override
  Future<void> logout({required String authorization}) async {
    await _client.request(
      method: 'DELETE',
      path: '/auth',
      headers: {'authorization': authorization},
    );
  }

  @override
  Future<void> logoutAll({required String authorization}) async {
    await _client.request(
      method: 'DELETE',
      path: '/auth/all',
      headers: {'authorization': authorization},
    );
  }
}
