import 'dart:io';

import 'package:revali_router/revali_router.dart';
import 'package:zonai/deps.dart';
import 'package:zonai_server/gen/swagger_assets.dart';
import 'package:revali_swagger_annotations/revali_swagger_annotations.dart'
    as swagger;

/// Thrown when the generated API contract is not available to this caller.
///
/// Deliberately says nothing about *why*. "Disabled in this build" and "you
/// are not an admin" are the same answer to an anonymous prober, so neither is
/// distinguishable from the endpoint simply not existing.
final class SchemaEndpointNotFoundException implements Exception {
  const SchemaEndpointNotFoundException();
}

@Controller('')
class RootController {
  const RootController();

  @Get('health')
  void health() {}

  @swagger.ApiHidden()
  @Get('favicon.ico')
  Future<Stream<List<int>>> favicon({required Headers responseHeaders}) async {
    final file = fs.file(fs.path.join(settings.imagesPath, 'favicon.ico'));
    if (!file.existsSync()) {
      throw const PhotoFileNotFoundException();
    }
    responseHeaders.mimeType = 'image/x-icon';
    responseHeaders.set(HttpHeaders.contentDisposition, 'inline');
    return file.openRead();
  }

  /// Optional brand mark for the dashboard. Unlike [favicon], nothing seeds
  /// this file -- its absence is what selects the letter-tile fallback, so a
  /// 404 here is the normal case, not an error.
  @swagger.ApiHidden()
  @Get('logo.png')
  Future<Stream<List<int>>> logo({required Headers responseHeaders}) async {
    final file = fs.file(fs.path.join(settings.imagesPath, 'logo.png'));
    if (!file.existsSync()) {
      throw const PhotoFileNotFoundException();
    }
    responseHeaders.mimeType = 'image/png';
    responseHeaders.set(HttpHeaders.contentDisposition, 'inline');
    return file.openRead();
  }

  @Get('swagger.json')
  Future<StringContent> swaggerJson({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    required Headers responseHeaders,
  }) async {
    await _assertSchemaReadable(authorization);
    responseHeaders.mimeType = 'application/json; charset=utf-8';
    return StringContent(kSwaggerJson);
  }

  @Get('swagger.yaml')
  Future<StringContent> swaggerYaml({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    required Headers responseHeaders,
  }) async {
    await _assertSchemaReadable(authorization);
    responseHeaders.mimeType = 'text/yaml; charset=utf-8';
    return StringContent(kSwaggerYaml);
  }

  /// Gates the generated API contract behind an admin token.
  ///
  /// These two routes serve the *complete* contract -- every route, every
  /// payload field, every enum -- which is a map of the attack surface handed
  /// to anyone who asks. It is useful during development and it is not
  /// something an anonymous caller needs, so it is treated like the other
  /// admin surfaces (`/dashboard`, `/crons`) rather than like `/health`.
  ///
  /// Set `ZONAI_DISABLE_SCHEMA_ENDPOINTS=true` to withdraw them entirely, for
  /// a deployment that has no reason to serve the contract at all.
  static Future<void> _assertSchemaReadable(String? authorization) async {
    if (schemaEndpointsDisabled) {
      // 404, not 403: a disabled endpoint should look absent rather than
      // confirm that this build has a schema endpoint worth returning to.
      throw const SchemaEndpointNotFoundException();
    }

    final jwt = await zonaiDB.parseJwt(_bearerToken(authorization));
    if (jwt == null || jwt.admin.isAdmin != true) {
      throw const SchemaEndpointNotFoundException();
    }
  }

  /// Whether the generated-contract routes are withdrawn for this process.
  static bool get schemaEndpointsDisabled =>
      Platform.environment['ZONAI_DISABLE_SCHEMA_ENDPOINTS']?.toLowerCase() ==
      'true';

  static String? _bearerToken(String? authorization) {
    if (authorization == null) return null;

    final trimmed = authorization.trim();
    const prefix = 'Bearer ';
    if (trimmed.length >= prefix.length &&
        trimmed.toLowerCase().startsWith(prefix.toLowerCase())) {
      final token = trimmed.substring(prefix.length).trim();
      return token.isEmpty ? null : token;
    }

    return null;
  }
}
