import 'package:revali_client/revali_client.dart';
import 'package:zonai_client/gen/client.dart';
import 'package:zonai_client/src/auth.dart';
import 'package:zonai_client/src/db.dart';
import 'package:zonai_client/src/emails.dart';
import 'package:zonai_client/src/photos.dart';
import 'package:zonai_client/src/utils/interceptor.dart';
import 'package:zonai_client/src/utils/zonai_storage_memory.dart';
import 'package:zonai_client/src/utils/zonai_storage_resolve.dart';

/// Main entry point for the Zonai HTTP client.
///
/// Wraps the generated [Server] and exposes higher-level service objects for
/// authentication ([auth]), the database ([db]), photos ([photos]), and email
/// ([email]) APIs.
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
/// Access tokens are managed automatically via [ZonaiStorage] and the
/// [Interceptor] X-Auth round-trip. After the first successful authentication
/// call the token is stored and injected into subsequent requests as
/// `Authorization: Bearer <token>`.
class ZonaiClient {
  /// Creates a [ZonaiClient] backed by an already-constructed [Server].
  ///
  /// Use this when you need full control over the [Server]'s HTTP client,
  /// storage, or base URL.
  ZonaiClient.server({required Server server})
    : _server = server,
      auth = Auth(auth: server.auth, storage: server.storage),
      email = Emails(email: server.email),
      photos = Photos(photos: server.photos),
      db = Db(db: server.db);

  /// Creates a [ZonaiClient] with optional [baseUrl] and [storageDirectory].
  ///
  /// [baseUrl] defaults to the `BASE_URL` compile-time environment variable, or
  /// `http://localhost:8080` if the variable is not set.
  ///
  /// [storageDirectory] sets the directory for file-backed [ZonaiStorage]. When
  /// omitted the client uses in-memory storage and the token is not persisted
  /// across process restarts.
  factory ZonaiClient({
    Uri? baseUrl,
    String? storageDirectory,
    Storage? storage,
    List<HttpInterceptor> extraInterceptors = const [],
  }) {
    final client = ZonaiClient.server(
      server: Server(
        baseUrl:
            baseUrl ??
            switch (const String.fromEnvironment('BASE_URL')) {
              final String value when value.isNotEmpty => Uri.parse(value),
              _ => Uri.parse('http://localhost:8080'),
            },
        storage: resolveZonaiStorage(
          storageDirectory: storageDirectory,
          storage: storage,
        ),
      ),
    );

    client._server.client.interceptors
      ..add(Interceptor(auth: client.auth))
      ..addAll(extraInterceptors);

    return client;
  }

  static ZonaiClient? _instance;

  /// Get the singleton instance of [ZonaiClient].
  ///
  /// If the instance is not already created, it will be created with the default
  /// base URL.
  ///
  /// The base URL is read from the environment variable `BASE_URL`.
  /// If the variable is not set, the default base URL is `http://localhost:8080`.
  static ZonaiClient get instance => _instance ??= ZonaiClient();

  /// Replaces the singleton instance.
  ///
  /// Useful in tests to inject a pre-configured client without going through
  /// the default initialization logic.
  static set instance(ZonaiClient client) {
    _instance = client;
  }

  final Server _server;

  /// Authentication service with automatic token management.
  final Auth auth;

  /// Email service for sending transactional emails.
  final Emails email;

  /// Photo service for uploading, downloading, and deleting photos.
  final Photos photos;

  /// Database service for CRUD operations and real-time streaming.
  final Db db;

  /// The underlying generated [Server] (e.g. for endpoints without a wrapper).
  Server get server => _server;

  /// Returns `true` if the server is reachable and healthy.
  Future<bool> health() async {
    await _server.root.health();
    return true;
  }
}
