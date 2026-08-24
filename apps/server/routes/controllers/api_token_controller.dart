// ! All `authorization` headers MUST have the same parameter name "authorization" so
// that we can properly inject the token into the request on the client side
import 'dart:io' show HttpHeaders;

import 'package:revali_router/revali_router.dart';
import 'package:revali_swagger_annotations/revali_swagger_annotations.dart'
    as swagger;
import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_server/src/handlers/api_token_handler.dart';

import '../components/black_list.dart';

/// API-token management for the dashboard (`docs/api-tokens-design.md` §8).
///
/// A controller of its own rather than four more methods on [AdminController],
/// the way `dashboard/maintenance` and `dashboard/push` sit beside
/// `dashboard`: these routes act on `_api_tokens`, not on the admin roster,
/// and the only thing they share with `/admin/members` is who may call them.
///
/// Everything here needs an **admin** JWT for the resolved `AsAdmin` table,
/// enforced in [ApiTokenHandler] rather than by a guard — same reasoning as
/// [AdminController], and the same `requireAdminCaller` doing it. That gate's
/// `parseJwt` refuses an API token, so a token cannot mint a token.
///
/// Tokens are addressed by **id**, and a unique prefix of one is accepted
/// wherever a full id is (`ZonaiDb.revokeApiToken` resolves it). An ambiguous
/// prefix is refused rather than guessed: picking the first match for a revoke
/// is how the wrong integration goes down.
@BlackList()
@Controller('admin/tokens')
class ApiTokenController {
  const ApiTokenController({required this.apiTokenHandler});

  final ApiTokenHandler apiTokenHandler;

  /// Every token, revoked ones included — the screen shows both.
  ///
  /// Never `token_hash`: the response is built by `buildTokenBody`, which is
  /// an allowlist rather than a serializer, so a column added to that table
  /// later is absent until somebody decides it belongs.
  @swagger.ApiResponse(
    200,
    description:
        '`{tokens: [{id, name, tokenPrefix, scope, claims, boundTable, '
        'boundUserId, createdBy, createdAt, expiresAt, revokedAt, '
        'lastUsedAt}]}`',
  )
  @swagger.ApiResponse(
    403,
    description:
        'No Bearer token, one that is not an admin for the resolved '
        '`AsAdmin` table, or an API token (which is never accepted here)',
  )
  @Get()
  Future<Map<String, Object?>> list({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
  }) async {
    return await apiTokenHandler.list(authorization);
  }

  /// Mint one. **The response carries the plaintext, and nothing ever will
  /// again** — the row keeps only its SHA-256.
  @swagger.ApiResponse(
    200,
    description:
        'The row, plus `token` — the plaintext credential, returned '
        'exactly once and unrecoverable afterwards',
  )
  @swagger.ApiResponse(
    400,
    description: 'A scope that could not have been meant',
  )
  @swagger.ApiResponse(
    403,
    description:
        'No Bearer token, one that is not an admin for the resolved '
        '`AsAdmin` table, or an API token',
  )
  @Post()
  Future<Map<String, Object?>> create({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required ApiTokenCreateBody body,
  }) async {
    return await apiTokenHandler.create(
      authorization: authorization,
      body: body,
    );
  }

  /// Stop it working, keep the record. Lands on the next request, with no
  /// restart.
  ///
  /// `POST` and not `DELETE`, because the row survives — see
  /// [ApiTokenHandler.revoke]. `DELETE /admin/tokens/:id` is the other thing,
  /// and one of them being a different verb is what stops the wrong one being
  /// called.
  @swagger.ApiResponse(200, description: 'The revoked row')
  @swagger.ApiResponse(404, description: 'No token with that id or prefix')
  @swagger.ApiResponse(403, description: 'Not an admin for the admin table')
  @Post(':id/revoke')
  Future<Map<String, Object?>> revoke({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Param() required String id,
  }) async {
    return await apiTokenHandler.revoke(authorization: authorization, id: id);
  }

  /// Remove the row entirely, audit trail and all.
  @swagger.ApiResponse(404, description: 'No token with that id or prefix')
  @swagger.ApiResponse(403, description: 'Not an admin for the admin table')
  @Delete(':id')
  Future<void> delete({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Param() required String id,
  }) async {
    await apiTokenHandler.delete(authorization: authorization, id: id);
  }
}
