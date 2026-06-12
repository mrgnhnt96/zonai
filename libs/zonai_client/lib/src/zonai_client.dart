import 'package:zonai_client/gen/client.dart';
import 'package:zonai_client/src/db.dart';
import 'package:zonai_client/src/emails.dart';
import 'package:zonai_client/src/photos.dart';
import 'package:zonai_client/src/utils/zonai_storage.dart';

/// Main entry point for the Zonai HTTP client.
///
/// Wraps the generated [Server] and exposes higher-level service objects for
/// the database ([db]), photos ([photos]), and email ([email]) APIs.
///
/// **Singleton usage** (memory storage, base URL from `BASE_URL` env var or
/// `http://localhost:8080`):
/// ```dart
/// final client = ZonaiClient.instance;
/// ```
///
/// **Explicit configuration** (file-backed storage, custom base URL):
/// ```dart
/// final client = ZonaiClient(
///   baseUrl: 'https://api.example.com',
///   storageDirectory: '/var/lib/myapp',
/// );
/// ```
///
/// Access tokens are managed automatically via [ZonaiStorage]. After the first
/// successful authentication call the token is stored and injected into every
/// subsequent request as `Authorization: Bearer <token>`.
class ZonaiClient {
  /// Creates a [ZonaiClient] backed by an already-constructed [Server].
  ///
  /// Use this when you need full control over the [Server]'s HTTP client,
  /// storage, or base URL.
  ZonaiClient.server({required this._server})
    : email = Emails(email: _server.email),
      photos = Photos(photos: _server.photos),
      db = Db(db: _server.db);

  /// Creates a [ZonaiClient] with optional [baseUrl] and [storageDirectory].
  ///
  /// [baseUrl] defaults to the `BASE_URL` compile-time environment variable, or
  /// `http://localhost:8080` if the variable is not set.
  ///
  /// [storageDirectory] sets the directory for file-backed [ZonaiStorage]. When
  /// omitted the client uses in-memory storage and the token is not persisted
  /// across process restarts.
  factory ZonaiClient({String? baseUrl, String? storageDirectory}) {
    return ZonaiClient.server(
      server: Server(
        baseUrl: switch (baseUrl ?? const String.fromEnvironment('BASE_URL')) {
          final String value when value.isNotEmpty => Uri.parse(value),
          _ => Uri.parse('http://localhost:8080'),
        },
        storage: switch (storageDirectory) {
          final String value when value.isNotEmpty => ZonaiStorage(
            directory: value,
          ),
          _ => ZonaiStorage.memory(),
        },
      ),
    );
  }

  static ZonaiClient? _instance;

  /// Get the singleton instance of [ZonaiClient].
  ///
  /// If the instance is not already created, it will be created with the default
  /// base URL.
  ///
  /// The base URL is read from the environment variable `BASE_URL`.
  /// If the variable is not set, the default base URL is `http://localhost:8080`.
  static ZonaiClient get instance => _instance ??= ZonaiClient.server(
    server: Server(
      baseUrl: switch (const String.fromEnvironment('BASE_URL')) {
        final value when value.isNotEmpty => Uri.parse(value),
        _ => Uri.parse('http://localhost:8080'),
      },
      storage: ZonaiStorage.memory(),
    ),
  );
  /// Replaces the singleton instance.
  ///
  /// Useful in tests to inject a pre-configured client without going through
  /// the default initialization logic.
  static set instance(ZonaiClient client) {
    _instance = client;
  }

  final Server _server;

  /// Email service for sending transactional emails.
  final Emails email;

  /// Photo service for uploading, downloading, and deleting photos.
  final Photos photos;

  /// Database service for CRUD operations and real-time streaming.
  final Db db;

  /// Returns `true` if the server is reachable and healthy.
  Future<bool> health() async {
    await _server.root.health();
    return true;
  }
}
