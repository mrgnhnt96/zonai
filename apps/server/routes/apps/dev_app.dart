import 'dart:io' show HttpHeaders, HttpServer, Platform;

import 'package:revali_router/revali_router.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai/deps.dart';
import 'package:zonai/zonai.dart' hide Args;
import 'package:zonai_logger/zonai_logger.dart';
import 'package:zonai_server/components/lifecycle_components/external_idp_provisioning.dart';
import 'package:zonai_server/components/lifecycle_components/trace_id.dart';
import 'package:zonai_server/config/server_binding.dart';
import 'package:zonai_server/src/handlers/auth_handler.dart';
import 'package:zonai_server/src/handlers/cron_handler.dart';
import 'package:zonai_server/src/handlers/dashboard_handler.dart';
import 'package:zonai_server/src/handlers/db_handler.dart';
import 'package:zonai_server/src/handlers/email_handler.dart';
import 'package:zonai_server/src/handlers/maintenance_handler.dart';
import 'package:zonai_server/src/handlers/photo_handler.dart';

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

/// What a response should say about cross-origin access, for a given request.
///
/// [allowOrigin] of `null` means emit no `Access-Control-Allow-Origin` at all,
/// which is what makes a browser refuse to hand the response to the page.
typedef CorsDecision = ({String? allowOrigin, bool allowCredentials});

/// Decides the CORS headers for a request whose `Origin` was [origin].
CorsDecision decideCors(String? origin, {Set<String> configured = const {}}) {
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

  return (allowOrigin: null, allowCredentials: false);
}

/// Replaces `@AllowOrigins.all()`, which expanded to `{'*'}`.
///
/// `{'*'}` matched every origin, and revali_router pairs a matched origin with
/// `Access-Control-Allow-Credentials: true` while reflecting the caller's own
/// `Origin` straight back (`run_origin_check.dart`, which sets both headers
/// unconditionally). Any page on any domain could therefore make credentialed
/// calls here and read the replies.
///
/// The decision is made here rather than in an `@AllowOrigins` annotation
/// because the generator re-emits an annotation's *value* into generated
/// source: a pattern containing `$` fails to parse, and one containing `\.`
/// or `\d` is silently rewritten to `.` and `d` -- an allow-list that looks
/// anchored and is not. A runtime regex is never round-tripped through
/// generated source, so it means what it says.
///
/// **What this does not cover.** `RunOriginCheck` runs before the router
/// decides an `OPTIONS` request is a preflight, and `RunOptions` returns that
/// already-populated response without running middleware -- so a *preflight*
/// still answers a hostile origin with reflected credentials. The real request
/// that follows is stripped by this component, so nothing can be read; but
/// closing the preflight itself needs a fix in revali_router. Nothing this app
/// can express reaches that path.
///
/// Typed as a [LifecycleComponent] deliberately: revali's generator matches
/// annotations against that marker to decide they contribute anything at all.
/// Drop the clause and `@Cors()` still compiles, codegen still succeeds, and
/// the component silently does nothing -- the same failure as
/// `known-issues.md` #1. `cors_policy_test.dart` pins it.
class Cors implements LifecycleComponent {
  const Cors();

  Future<Response> wrap(Context context, NextResponse next) async {
    final result = await next();

    final decision = decideCors(
      context.request.headers.get('origin'),
      configured: configuredOrigins(),
    );

    if (decision.allowOrigin case final allowed?) {
      result.headers.set(HttpHeaders.accessControlAllowOriginHeader, allowed);
    } else {
      result.headers.remove(HttpHeaders.accessControlAllowOriginHeader);
    }

    if (!decision.allowCredentials) {
      result.headers.remove(HttpHeaders.accessControlAllowCredentialsHeader);
    }

    // The allowed origin is reflected from the request, so the response and
    // its `Access-Control-Allow-Origin` both vary by `Origin`. Without this a
    // shared cache can hand one origin's response -- carrying that origin's
    // Allow-Origin -- to a different one.
    result.headers.add('vary', 'origin');

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
  Future<void> configureDependencies(DI di) async {
    di.registerFactory(DbHandler.new);
    di.registerFactory(AuthHandler.new);
    di.registerFactory(DashboardHandler.new);
    di.registerFactory(CronHandler.new);
    di.registerFactory(MaintenanceHandler.new);
    di.registerFactory(EmailHandler.new);
    di.registerFactory(PhotoHandler.new);
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
