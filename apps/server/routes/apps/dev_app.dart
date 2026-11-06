import 'dart:io' show HttpHeaders, HttpServer, Platform;

import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart' hide Args;
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_server/components/lifecycle_components/external_idp_provisioning.dart';
import 'package:zonai_server/components/lifecycle_components/trace_id.dart';
import 'package:zonai_server/config/server_binding.dart';
import 'package:zonai_server/src/handlers/admin_handler.dart';
import 'package:zonai_server/src/handlers/api_token_handler.dart';
import 'package:zonai_server/src/handlers/auth_handler.dart';
import 'package:zonai_server/src/handlers/cron_handler.dart';
import 'package:zonai_server/src/handlers/dashboard_handler.dart';
import 'package:zonai_server/src/handlers/db_handler.dart';
import 'package:zonai_server/src/handlers/email_handler.dart';
import 'package:zonai_server/src/handlers/maintenance_handler.dart';
import 'package:zonai_server/src/handlers/photo_handler.dart';
import 'package:zonai_server/src/handlers/push_handler.dart';
import 'package:zonai_server/src/handlers/webhook_handler.dart';

import '../components/exception_catcher.dart';

/// Origins allowed to make *credentialed* cross-origin requests by default.
///
/// The loopback origins the dashboard is actually served from, which is the
/// whole surface an unconfigured server has now that [ServerBinding] defaults
/// to loopback. Anything else is an explicit decision -- see
/// [configuredOrigins].
///
/// Anchored at both ends. revali_router matches its own patterns with
/// [RegExp.hasMatch], which is a substring test, and an unanchored
/// `localhost` would also match `https://localhost.evil.example` -- a domain
/// anyone can register.
final loopbackOrigin = RegExp(
  r'^https?://(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$',
);

/// Extra origins allowed to send credentialed requests, from the environment.
///
/// `ZONAI_ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com`.
/// Read at runtime rather than baked in with `String.fromEnvironment` so a
/// released binary can be pointed at a deployment's real front end without
/// being rebuilt.
Set<String> configuredOrigins() =>
    parseOrigins(Platform.environment['ZONAI_ALLOWED_ORIGINS']);

/// Parses a comma-separated origin allow-list.
Set<String> parseOrigins(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const {};
  return {
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  };
}

/// Whether [origin] may be granted a credentialed cross-origin response.
bool isAllowedOrigin(String origin, {Set<String> configured = const {}}) =>
    configured.contains(origin) || loopbackOrigin.hasMatch(origin);

/// Decides the CORS grant for a request whose `Origin` was [origin].
///
/// The granted origin is either the caller's own (only ever with credentials)
/// or `*` (never with credentials).
CorsGrant decideCors(String? origin, {Set<String> configured = const {}}) {
  // No `Origin` means this is not a cross-origin browser request at all --
  // a native client, curl, or server-to-server. revali_router answers those
  // with `*`, which is fine on its own and must never carry credentials:
  // `*` plus credentials is rejected by every browser, and a server that
  // meant it would be granting every origin at once.
  if (origin == null) {
    return (allowOrigin: '*', allowCredentials: false);
  }

  if (isAllowedOrigin(origin, configured: configured)) {
    return (allowOrigin: origin, allowCredentials: true);
  }

  // An origin nobody listed -- a customer's site running the web SDK, which
  // no operator can enumerate. It gets the same public grant as a request
  // with no Origin: the browser hands it the reply, but sends no cookies or
  // HTTP auth with the request and exposes nothing that relies on them.
  // Refusing it outright (no Allow-Origin) did not stop the request: a POST
  // was still stored, and the page only saw a network error.
  return (allowOrigin: '*', allowCredentials: false);
}

/// Applies [decideCors] to every request revali_router admits.
///
/// `RunOriginCheck` asks this before anything else runs, which is the only
/// point that reaches an `OPTIONS` preflight: `RunOptions` answers those
/// without running a lifecycle component, so [Cors] alone would leave
/// revali_router's default in place there -- the caller's own `Origin`,
/// reflected, with credentials.
final class ZonaiCorsPolicy extends CorsPolicy {
  const ZonaiCorsPolicy({this.configured = configuredOrigins});

  /// Reads the listed origins, once per request.
  final Set<String> Function() configured;

  @override
  CorsGrant grant(String? origin) =>
      decideCors(origin, configured: configured());
}

/// Holds a finished response to the same decision as [ZonaiCorsPolicy].
///
/// [ZonaiCorsPolicy] only writes the response a route starts with, so this is
/// what covers a response built some other way, such as one from an exception
/// catcher. It also marks a response from a request with no `Origin` as varying
/// on it, which `RunOriginCheck` does not: a cache that stored that `*` would
/// otherwise replay it to a listed origin expecting its credentialed grant.
///
/// The decision is made at runtime rather than in an `@AllowOrigins` annotation
/// because the generator re-emits an annotation's *value* into generated
/// source: a pattern containing `$` fails to parse, and one containing `\.`
/// or `\d` is silently rewritten to `.` and `d` -- an allow-list that looks
/// anchored and is not. A runtime regex is never round-tripped through
/// generated source, so it means what it says.
///
/// Typed as a [LifecycleComponent] deliberately: revali's generator matches
/// annotations against that marker to decide they contribute anything at all.
/// Drop the clause and `@Cors()` still compiles, codegen still succeeds, and
/// the component silently does nothing -- the same failure as
/// the bug fixed in 111b8dfd. `cors_policy_test.dart` pins it.
class Cors implements LifecycleComponent {
  const Cors({this.policy = const ZonaiCorsPolicy()});

  final CorsPolicy policy;

  Future<Response> wrap(Context context, NextResponse next) async {
    final result = await next();

    final grant = policy.grant(context.request.headers.get('origin'));

    result.headers.set(
      HttpHeaders.accessControlAllowOriginHeader,
      grant.allowOrigin,
    );

    if (grant.allowCredentials) {
      result.headers.set(
        HttpHeaders.accessControlAllowCredentialsHeader,
        'true',
      );
    } else {
      result.headers.remove(HttpHeaders.accessControlAllowCredentialsHeader);
    }

    // The allowed origin is reflected from the request, so the response and
    // its `Access-Control-Allow-Origin` both vary by `Origin`. Without this a
    // shared cache can hand one origin's response -- carrying that origin's
    // Allow-Origin -- to a different one.
    final vary = result.headers.get(HttpHeaders.varyHeader) ?? '';
    final varies = vary
        .split(',')
        .any((value) => value.trim().toLowerCase() == 'origin');
    if (!varies) result.headers.add(HttpHeaders.varyHeader, 'Origin');

    return result;
  }
}

@Exceptions()
@Cors()
@Trace()
@ExternalIdpProvisioning()
@App(flavor: 'dev')
final class DevApp extends AppConfig {
  DevApp()
    : super(
        host: ServerBinding.host,
        port: ServerBinding.port,
        prefix: '',
        // Multi-isolate accept only after host-side IPC caches / in-process
        // sanitize — otherwise each isolate would spawn its own Mailman pools
        // against one SQLite file. Opt in with ZONAI_HTTP_WORKERS; default 1.
        workers: _httpWorkers,
      );

  static int get _httpWorkers {
    final raw = Platform.environment['ZONAI_HTTP_WORKERS'];
    final parsed = int.tryParse(raw ?? '');
    if (parsed == null || parsed < 1) return 1;
    return parsed;
  }

  TrustedProxy _trustedProxy = const TrustedProxy();

  @override
  TrustedProxy get trustedProxy => _trustedProxy;

  @override
  CorsPolicy get cors => const ZonaiCorsPolicy();

  @override
  Future<void> configureDependencies(DI di) async {
    di.registerFactory(DbHandler.new);
    di.registerFactory(AuthHandler.new);
    di.registerFactory(AdminHandler.new);
    di.registerFactory(ApiTokenHandler.new);
    di.registerFactory(DashboardHandler.new);
    di.registerFactory(CronHandler.new);
    di.registerFactory(MaintenanceHandler.new);
    di.registerFactory(EmailHandler.new);
    di.registerFactory(PhotoHandler.new);
    di.registerFactory(PushHandler.new);
    di.registerFactory(WebhookHandler.new);
  }

  @override
  void onServerStarted(HttpServer server) {
    super.onServerStarted(server);
    print('Access the UI at http://${server.address.host}:${server.port}/_');
  }

  @override
  Future<HttpServer> runStartup(Future<HttpServer> Function() startup) async {
    final parentLogger = read(
      loggerProvider,
      orElse: () => Logger.print(level: .info),
    );

    return await runMergedScoped(
      () async {
        final config = await zonaiDB.getConfig();
        _trustedProxy = TrustedProxy(
          headers: config.trustedProxy.headers,
          useLeftmostIp: config.trustedProxy.useLeftmostIp,
        );
        return startup();
      },
      override: {loggerProvider.overrideWith(() => parentLogger)},
      includeIfAbsent: {
        argsProvider,
        courierProvider,
        envProvider,
        cleanUpProvider,
        mutationsProvider,
        zonaiDbProvider,
        extensionsProvider,
        executableStopProvider,
        rateLimiterProvider,
        rateLimitsProvider,
        rulesProvider,
        operationsProvider,
        configProvider,
        migrateProvider,
        fsProvider,
        processProvider,
        settingsProvider.overrideWith(() {
          if (kIsCompiled) {
            return Settings.load();
          }

          final settings = Settings.load(fs.path.join('..', 'playground'));
          return settings;
        }),
      },
    );
  }
}
