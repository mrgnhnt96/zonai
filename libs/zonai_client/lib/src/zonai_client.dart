import 'package:zonai_client/gen/client.dart';
import 'package:zonai_client/src/db.dart';
import 'package:zonai_client/src/emails.dart';
import 'package:zonai_client/src/photos.dart';

class ZonaiClient {
  ZonaiClient({required this._server})
    : email = Emails(email: _server.email),
      photos = Photos(photos: _server.photos),
      db = Db(db: _server.db);

  static ZonaiClient? _instance;

  /// Get the singleton instance of [ZonaiClient].
  ///
  /// If the instance is not already created, it will be created with the default
  /// base URL.
  ///
  /// The base URL is read from the environment variable `BASE_URL`.
  /// If the variable is not set, the default base URL is `http://localhost:8080`.
  static ZonaiClient get instance => _instance ??= ZonaiClient(
    server: Server(
      baseUrl: switch (const String.fromEnvironment('BASE_URL')) {
        final value when value.isNotEmpty => Uri.parse(value),
        _ => Uri.parse('http://localhost:8080'),
      },
    ),
  );
  static set instance(ZonaiClient client) {
    _instance = client;
  }

  final Server _server;
  final Emails email;
  final Photos photos;
  final Db db;

  Future<bool> health() async {
    await _server.root.health();
    return true;
  }
}
