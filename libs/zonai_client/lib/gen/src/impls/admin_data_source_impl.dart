part of '../../client.dart';

class AdminDataSourceImpl implements AdminDataSource {
  const AdminDataSourceImpl({
    required RevaliClient client,
    required Storage storage,
  }) : _client = client,
       _storage = storage;

  final RevaliClient _client;

  final Storage _storage;

  @override
  Future<Map<String, Object?>> members({String? authorization}) async {
    final response = await _client.request(
      method: 'GET',
      path: '/admin/members',
      headers: {'authorization': authorization},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>> passwordResetRequirement({
    required String email,
    required String table,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'GET',
      path: '/admin/members/${email}/require-password-reset',
      headers: {'authorization': authorization},
      query: {'table': table},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>> invite({
    required AdminInviteBody body,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/admin/invites',
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
  Future<Map<String, Object?>> requirePasswordReset({
    required String email,
    required String table,
    String? reason,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'POST',
      path: '/admin/members/${email}/require-password-reset',
      headers: {'authorization': authorization},
      query: {'table': table, 'reason': reason},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<void> revokeInvite({
    required String email,
    String? authorization,
  }) async {
    await _client.request(
      method: 'DELETE',
      path: '/admin/invites/${email}',
      headers: {'authorization': authorization},
    );
  }

  @override
  Future<Map<String, Object?>> removeMember({
    required String email,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'DELETE',
      path: '/admin/members/${email}',
      headers: {'authorization': authorization},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }

  @override
  Future<Map<String, Object?>> clearPasswordReset({
    required String email,
    required String table,
    String? authorization,
  }) async {
    final response = await _client.request(
      method: 'DELETE',
      path: '/admin/members/${email}/require-password-reset',
      headers: {'authorization': authorization},
      query: {'table': table},
    );

    final _body = await response.transform(utf8.decoder).join();

    if (jsonDecode(_body) case {'data': final Map data}) {
      return data.map((key, value) => MapEntry((key as String), value));
    }

    throw Exception('Invalid response');
  }
}
