// ! All `authorization` headers MUST have the same parameter name "authorization" so
// that we can properly inject the token into the request on the client side
import 'dart:io' show HttpHeaders;

import 'package:revali_router/revali_router.dart';
import 'package:revali_swagger_annotations/revali_swagger_annotations.dart'
    as swagger;
import 'package:zonai_schema/zonai_schema.dart';
import 'package:zonai_server/src/handlers/admin_handler.dart';

import '../components/admin_invite_rate_limit.dart';
import '../components/black_list.dart';

// ! Spell the rate-limit operation out as `RateLimitOperation.x`, never as the
// dot-shorthand `.x` -- revali's server generator cannot resolve a dot-shorthand
// annotation argument. See docs/revali-dot-shorthand-codegen.md.

/// Admin management for the dashboard (`docs/admin-invite-design.md` §5 W1).
///
/// Everything here needs an **admin** JWT for the resolved `AsAdmin` table,
/// enforced in [AdminHandler] rather than by a guard. A guard would have to
/// resolve that table and parse the token itself, duplicating the check the
/// handler has to make anyway — and two copies of an authorization rule is one
/// copy too many.
///
/// Invites are addressed by **email**, not by an opaque id, because that is
/// what the runtime is keyed on: `ZonaiDb.revokeAdminInvite` and
/// `removeAdmin` both take `email`, and `listAdminInvites` returns no id to
/// address a row by. `Uri.pathSegments` percent-decodes, so
/// `DELETE /admin/invites/a%2Bb%40example.com` reaches the handler as
/// `a+b@example.com` — which a query parameter would not, since `+` decodes to
/// a space there.
@BlackList()
@Controller('admin')
class AdminController {
  const AdminController({required this.adminHandler});

  final AdminHandler adminHandler;

  /// Current admins **and** pending invites, in one response.
  ///
  /// One route rather than two because the Admins screen renders both together
  /// and a second round trip would let it paint a half-answered page. Design
  /// §5 W2.
  ///
  /// `admins` never carries a password hash or any other `Secret` column: it
  /// comes from `ZonaiDb.listAdmins()`, which sanitizes with no JWT. `invites`
  /// never carries the invite token's hash. See [buildMembersBody].
  @swagger.ApiResponse(
    200,
    description:
        '`{admins: [...], invites: [{email, invitedAt, expiresAt, '
        'invitedByEmail}]}`',
  )
  @swagger.ApiResponse(
    403,
    description:
        'No Bearer token, or one that is not an '
        'admin for the resolved `AsAdmin` table',
  )
  @Get('members')
  Future<Map<String, Object?>> members({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
  }) async {
    return await adminHandler.members(authorization);
  }

  /// Invite [AdminInviteBody.email] to become an admin (design §3.1).
  ///
  /// The response carries the normalized address, the table, the expiry and
  /// whether a live invite was resent rather than duplicated — and never the
  /// token, which exists only in the email (design §4 item 8). The 429 has two
  /// independent sources, and they are not redundant: [AdminInviteRateLimit]
  /// bounds invites per admin table per client IP, while `_inviteAdmin` bounds
  /// repeat invites to one address to one a minute.
  @swagger.ApiResponse(
    200,
    description: '`{email, table, expiresAt, isResend}`',
  )
  @swagger.ApiResponse(
    403,
    description:
        'No Bearer token, or one that is not an '
        'admin for the resolved `AsAdmin` table',
  )
  @swagger.ApiResponse(
    429,
    description:
        'adminInvite rate limit exceeded, or this address was '
        'already invited within the last minute',
  )
  @AdminInviteRateLimit()
  @Post('invites')
  Future<Map<String, Object?>> invite({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Body() required AdminInviteBody body,
  }) async {
    return await adminHandler.invite(
      authorization: authorization,
      email: body.email,
    );
  }

  /// Revoke a pending invite: the link stops working (design §3.4).
  ///
  /// Idempotent, and answers the same for an address that was never invited as
  /// for one whose invite it just cleared — `_expireOldChallenges` has nothing
  /// to report either way. Returning "no such invite" would turn this into an
  /// oracle for which addresses have pending invites.
  @swagger.ApiResponse(
    403,
    description:
        'No Bearer token, or one that is not an '
        'admin for the resolved `AsAdmin` table',
  )
  @Delete('invites/:email')
  Future<void> revokeInvite({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Param() required String email,
  }) async {
    await adminHandler.revokeInvite(authorization: authorization, email: email);
  }

  /// Remove an admin and revoke their sessions (design §3.4).
  ///
  /// The two refusals are the point of design §4 item 6: an admin cannot
  /// remove themselves (403) and the last admin cannot be removed at all
  /// (409). A dashboard that can lock everyone out is a bug, not a feature.
  @swagger.ApiResponse(200, description: 'The removed admin row, sanitized')
  @swagger.ApiResponse(
    403,
    description:
        'No Bearer token, one that is not an admin for the resolved '
        '`AsAdmin` table, or an admin removing themselves',
  )
  @swagger.ApiResponse(409, description: 'That is the table\'s last admin')
  @Delete('members/:email')
  Future<Map<String, Object?>> removeMember({
    @Header(HttpHeaders.authorizationHeader) required String? authorization,
    @Param() required String email,
  }) async {
    return await adminHandler.removeMember(
      authorization: authorization,
      email: email,
    );
  }
}
