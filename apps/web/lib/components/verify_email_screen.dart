import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import 'sign_in_screen.dart';

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
    final signedIn = context.read(authProvider);
    context.read(authRouteProvider.notifier).navigateTo(
      signedIn ? AuthRoutes.home : AuthRoutes.signIn,
    );
  }

  @override
  Component build(BuildContext context) {
    return SignInScreen(
      child: div(classes: 'card', [
        if (_success) ...[
          h1(classes: 'title', [.text('Email verified')]),
          p(classes: 'subtitle', [.text('Your email address has been verified.')]),
          button(
            classes: 'submit',
            type: .button,
            onClick: _continue,
            [.text(context.watch(authProvider) ? 'Continue' : 'Sign in')],
          ),
        ] else if (_loading) ...[
          h1(classes: 'title', [.text('Verify your email')]),
          p(classes: 'subtitle', [.text('Verifying your email address…')]),
        ] else if (_error case final error?) ...[
          h1(classes: 'title', [.text('Verify your email')]),
          p(classes: 'error', [.text(error)]),
          button(
            classes: 'submit',
            type: .button,
            onClick: _continue,
            [.text(context.watch(authProvider) ? 'Continue' : 'Back to sign in')],
          ),
        ],
      ]),
    );
  }
}
