import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_provider.dart';
import '../utils/jwt_payload.dart';
import '../utils/zonai_cookie.dart';

final sessionUserProvider = Provider<SessionUser?>((ref) {
  ref.watch(authProvider);
  if (!ref.binding.isClient) return null;

  final token = ZonaiCookie.authToken.read();
  if (token == null || token.isEmpty) return null;

  return sessionUserFromToken(token);
});
