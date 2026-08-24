import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_token_client.dart';
import '../utils/api_tokens.dart';
import '../utils/user_facing_error.dart';
import 'toast_provider.dart';

/// Every API token on the deployment, loaded client-side.
///
/// SSR answers an empty list rather than fetching, the same as
/// `adminMembersProvider`: `GET /admin/tokens` needs the caller's bearer
/// token, and the server render has no session of its own to spend.
final apiTokensProvider = AsyncNotifierProvider<ApiTokensNotifier, List<ApiTokenRow>>(ApiTokensNotifier.new);

class ApiTokensNotifier extends AsyncNotifier<List<ApiTokenRow>> {
  @override
  Future<List<ApiTokenRow>> build() async {
    if (!ref.binding.isClient) return const [];

    return await fetchApiTokens(server: ref.read(revaliServerProvider));
  }

  Future<void> refresh() async {
    if (!ref.binding.isClient) return;
    ref.invalidateSelf();
  }

  /// Mints a token and returns the plaintext **once**.
  ///
  /// The secret is returned rather than stored in this notifier's state on
  /// purpose: state here is rebuilt from the server on every `invalidateSelf`,
  /// and a value that cannot be re-fetched must not live somewhere that
  /// expects to re-fetch it. The screen holds it for exactly as long as the
  /// reveal is open.
  ///
  /// Null means it failed and the operator has already been told why.
  Future<({ApiTokenRow row, String secret})?> mint(Map<String, Object?> body) async {
    try {
      final minted = await mintApiToken(server: ref.read(revaliServerProvider), body: body);
      ref.invalidateSelf();
      return minted;
    } catch (error) {
      ref.read(toastProvider.notifier).showError(userFacingError(error));
      return null;
    }
  }

  /// Stops [id] working on the next request, and keeps the record.
  Future<void> revoke({required String id, required String name}) async {
    try {
      await revokeApiToken(server: ref.read(revaliServerProvider), id: id);
      ref.read(toastProvider.notifier).showSuccess('Revoked "$name". It stops working on its next request.');
    } catch (error) {
      ref.read(toastProvider.notifier).showError(userFacingError(error));
    }
    ref.invalidateSelf();
  }

  /// Removes the row entirely.
  Future<void> delete({required String id, required String name}) async {
    try {
      await deleteApiToken(server: ref.read(revaliServerProvider), id: id);
      ref.read(toastProvider.notifier).showSuccess('Deleted "$name".');
    } catch (error) {
      ref.read(toastProvider.notifier).showError(userFacingError(error));
    }
    ref.invalidateSelf();
  }
}
