/// Jaspr SSR and static asset serving for compiled Revali builds.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:jaspr/server.dart';
import 'package:revali_router/revali_router.dart' hide Request, Response;
import 'package:zonai/gen/web/web_assets.dart' as embedded;

import '../auth/auth_routes.dart';
import '../main.server.options.dart';
import 'web_app_document.dart';

var _jasprInitialized = false;

/// Initializes Jaspr once before rendering or serving assets.
void ensureJasprInitialized() {
  if (_jasprInitialized) {
    return;
  }

  Jaspr.initializeApp(options: defaultServerOptions);
  _jasprInitialized = true;
}

/// Suffixes for compiled Jaspr client assets (not the same as [Jaspr.allowedPathSuffixes],
/// which only covers SSR page routes like `.html`).
const _jasprStaticAssetSuffixes = {'css', 'ico', 'js', 'json', 'map', 'png', 'svg', 'wasm'};

/// Returns true when [path] looks like a static Jaspr asset request.
bool isJasprStaticAssetPath(String path) {
  final segment = path.split('/').where((part) => part.isNotEmpty).lastOrNull ?? '';
  if (!segment.contains('.')) {
    return false;
  }

  final suffix = segment.split('.').last.toLowerCase();
  return _jasprStaticAssetSuffixes.contains(suffix);
}

/// Revali's cookie serializer appends `"; "` after each entry, which makes Jaspr
/// split out an empty segment and fail cookie parsing during SSR.
String? _cookieHeaderForJaspr(Headers headers) {
  final parts = <String>[];
  for (final entry in headers.cookies.entries) {
    final name = entry.key.trim();
    final value = entry.value?.trim();
    if (name.isEmpty || value == null || value.isEmpty) {
      continue;
    }
    parts.add('$name=$value');
  }
  return parts.isEmpty ? null : parts.join('; ');
}

/// Maps a Revali [context] to a shelf [Request] for Jaspr rendering.
Request toShelfRequest(Context context) {
  final headers = <String, String>{};
  context.request.headers.forEach((key, values) {
    if (key.toLowerCase() == HttpHeaders.cookieHeader) {
      return;
    }
    headers[key] = values.join(',');
  });

  final cookieHeader = _cookieHeaderForJaspr(context.request.headers);
  if (cookieHeader != null) {
    headers[HttpHeaders.cookieHeader] = cookieHeader;
  }

  final requestUri = context.request.uri;
  final host = headers['host'] ?? 'localhost:8080';
  final absoluteUri = requestUri.hasScheme
      ? requestUri
      : Uri.parse(
          'http://$host${requestUri.path.isEmpty ? '/' : requestUri.path}',
        ).replace(queryParameters: requestUri.queryParameters.isEmpty ? null : requestUri.queryParameters);

  return Request(context.request.method, absoluteUri, headers: headers);
}

/// Strips the mount prefix from asset URLs when the app is mounted under a subpath.
String jasprAssetPathFromRequest(String path) {
  final mount = AuthRoutes.mountPath;
  if (mount == '/' || mount.isEmpty) {
    return path;
  }

  if (path == mount) {
    return '/';
  }

  final prefix = '$mount/';
  if (path.startsWith(prefix)) {
    return path.substring(mount.length);
  }

  return path;
}

/// Serves Jaspr client assets from embedded constants.
Future<Response?> tryServeJasprAsset(Request request) async {
  final assetPath = jasprAssetPathFromRequest(request.requestedUri.path);
  final relativePath = assetPath.startsWith('/') ? assetPath.substring(1) : assetPath;
  if (relativePath.isEmpty || relativePath.contains('..')) {
    return null;
  }

  final asset = embedded.lookupJasprWebAsset(relativePath);
  if (asset == null) {
    return null;
  }

  final headers = <String, String>{};
  if (asset.contentType case final contentType?) {
    headers[HttpHeaders.contentTypeHeader] = contentType;
  }

  if (request.method == 'HEAD') {
    return Response(200, headers: headers);
  }

  var bytes = Uint8List.fromList(asset.bytes);
  if (relativePath.endsWith('.js') && embedded.lookupJasprWebAsset('$relativePath.map') == null) {
    final content = utf8.decode(bytes);
    final stripped = content.replaceFirst(RegExp(r'[\n\r]*//# sourceMappingURL=.*$'), '');
    if (stripped.length != content.length) {
      bytes = Uint8List.fromList(utf8.encode(stripped));
    }
  }

  return Response.ok(bytes, headers: headers);
}

/// Renders the Zonai web app document for the given shelf [request].
Future<ResponseLike> renderWebApp(Request request) async {
  ensureJasprInitialized();
  return renderComponent(buildWebAppDocument(), request: request);
}

/// Applies a Jaspr [ResponseLike] to a Revali [context].
void applyJasprResponse(Context context, ResponseLike rendered) {
  context.response.statusCode = rendered.statusCode;
  for (final entry in rendered.headers.entries) {
    context.response.headers.add(entry.key, entry.value.join(','));
  }
  context.response.headers.mimeType = 'text/html; charset=utf-8';
  context.response.body = rendered.body;
}

/// Applies a shelf [Response] to a Revali [context].
Future<void> applyShelfResponse(Context context, Response response) async {
  context.response.statusCode = response.statusCode;
  for (final entry in response.headers.entries) {
    context.response.headers.add(entry.key, entry.value);
  }

  if (response.headers[HttpHeaders.contentTypeHeader] case final contentType?) {
    context.response.headers.mimeType = contentType;
  }

  final chunks = await response.read().toList();
  context.response.body = Uint8List.fromList(chunks.expand((chunk) => chunk).toList());
}
