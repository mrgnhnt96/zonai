import 'dart:async';

import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import 'sign_in_screen.dart';
import 'theme/theme_components.dart';

/// Verifies a magic link from query parameters and signs the user in.
class MagicLinkVerifyScreen extends StatefulComponent {
  const MagicLinkVerifyScreen({super.key});

  @override
  State<MagicLinkVerifyScreen> createState() => MagicLinkVerifyScreenState();
}

class MagicLinkVerifyScreenState extends State<MagicLinkVerifyScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_verifyFromUrl);
  }

  Future<void> _verifyFromUrl() async {
    final token = Uri.parse(context.url).queryParameters['s'];

    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This sign-in link is invalid or incomplete.';
      });
      return;
    }

    if (!context.binding.isClient) {
      return;
    }

    try {
      await context.read(authProvider.notifier).verifyMagicLink(secret: token);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This sign-in link is invalid or has expired.';
      });
    }
  }

  void _returnToSignIn() {
    context.read(authRouteProvider.notifier).navigateTo(AuthRoutes.signIn);
  }

  @override
  Component build(BuildContext context) {
    return SignInScreen(
      tagline: 'Magic link sign-in',
      child: AuthFormCard(
        children: [
          if (_loading) ...[
            const ZonaiPageTitle('Signing you in'),
            const ZonaiPageSubtitle('Verifying your sign-in link…'),
          ] else if (_error case final error?) ...[
            const ZonaiPageTitle('Sign-in link'),
            ZonaiErrorText(error),
            AuthActions(
              children: [
                ZonaiButton(
                  fullWidth: true,
                  onClick: _returnToSignIn,
                  child: .text('Back to sign in'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
