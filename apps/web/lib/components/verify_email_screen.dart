import 'dart:async';

import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:universal_web/web.dart' as web;

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import 'sign_in_screen.dart';
import 'theme/theme_components.dart';

/// Verifies an email address from a link query parameter.
class VerifyEmailScreen extends StatefulComponent {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => VerifyEmailScreenState();
}

class VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _loading = true;
  bool _success = false;
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
        _error = 'This verification link is invalid or incomplete.';
      });
      return;
    }

    if (!context.binding.isClient) {
      return;
    }

    try {
      await context.read(authProvider.notifier).verifyEmail(token: token);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'This verification link is invalid or has expired.';
      });
    }
  }

  void _continue() {
    if (context.read(authProvider)) {
      web.window.location.assign(AuthRoutes.toUrlPath(AuthRoutes.home));
      return;
    }
    context.goApp(AuthRoutes.signIn);
  }

  @override
  Component build(BuildContext context) {
    return SignInScreen(
      tagline: 'Email verification',
      child: AuthFormCard(
        children: [
          if (_success) ...[
            AuthSentHeader(icon: '✓', title: 'Email verified', subtitle: 'Your email address has been verified.'),
            AuthActions(
              children: [
                ZonaiButton(
                  fullWidth: true,
                  onClick: _continue,
                  child: .text(context.watch(authProvider) ? 'Continue' : 'Sign in'),
                ),
              ],
            ),
          ] else if (_loading) ...[
            const ZonaiPageTitle('Verify your email'),
            const ZonaiPageSubtitle('Verifying your email address…'),
          ] else if (_error case final error?) ...[
            const ZonaiPageTitle('Verify your email'),
            ZonaiErrorText(error),
            AuthActions(
              children: [
                ZonaiButton(
                  fullWidth: true,
                  onClick: _continue,
                  child: .text(context.watch(authProvider) ? 'Continue' : 'Back to sign in'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
