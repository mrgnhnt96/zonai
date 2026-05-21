import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import '../auth/supported_auth_types_provider.dart';
import 'magic_link_sign_in_screen.dart';
import 'magic_link_verify_screen.dart';
import 'otp_sign_in_screen.dart';
import 'reset_password_confirm_screen.dart';
import 'reset_password_request_screen.dart';
import 'sign_in_screen.dart';
import 'verify_email_screen.dart';

/// Chooses the sign-in screen from supported auth types and the current path.
class LoginFlow extends StatelessComponent {
  const LoginFlow({super.key});

  @override
  Component build(BuildContext context) {
    final authTypes = context.watch(supportedAuthTypesProvider);
    final path = context.watch(authRouteProvider);

    if (AuthRoutes.isMagicLinkCallbackPath(path)) {
      return const MagicLinkVerifyScreen();
    }

    if (AuthRoutes.isResetPasswordCallbackPath(path)) {
      return const ResetPasswordConfirmScreen();
    }

    if (AuthRoutes.isResetPasswordRequestPath(path)) {
      return const ResetPasswordRequestScreen();
    }

    if (AuthRoutes.isVerifyEmailCallbackPath(path)) {
      return const VerifyEmailScreen();
    }

    if (authTypes.isEmpty) {
      return const SignInScreen(child: _SignInMessage('No sign-in methods are configured.'));
    }

    if (authTypes.length == 1 && AuthRoutes.isSignInRoot(path)) {
      if (!context.binding.isClient) {
        return switch (authTypes.single) {
          .password => const PasswordSignInScreen(),
          .otp => const OtpSignInScreen(),
          .magicLink => const MagicLinkSignInScreen(),
        };
      }
      return _RedirectToAuthType(authType: authTypes.single);
    }

    final selected = AuthRoutes.typeFromPath(path);
    if (selected != null && authTypes.contains(selected)) {
      return switch (selected) {
        .password => const PasswordSignInScreen(),
        .otp => const OtpSignInScreen(),
        .magicLink => const MagicLinkSignInScreen(),
      };
    }

    if (!AuthRoutes.isSignInRoot(path)) {
      return _RedirectToAuthType(authType: authTypes.first);
    }

    return const AuthTypePickerScreen();
  }
}

class _RedirectToAuthType extends StatefulComponent {
  const _RedirectToAuthType({required this.authType});

  final AuthType authType;

  @override
  State<_RedirectToAuthType> createState() => _RedirectToAuthTypeState();
}

class _RedirectToAuthTypeState extends State<_RedirectToAuthType> {
  @override
  void initState() {
    super.initState();
    if (!context.binding.isClient) {
      return;
    }
    scheduleMicrotask(() {
      if (!mounted) return;
      context.read(authRouteProvider.notifier).navigateTo(AuthRoutes.forType(component.authType));
    });
  }

  @override
  Component build(BuildContext context) {
    return const SignInScreen(child: _SignInLoading());
  }
}

class _SignInLoading extends StatelessComponent {
  const _SignInLoading();

  @override
  Component build(BuildContext context) {
    return div(classes: 'card', [
      h1(classes: 'title', [.text('Sign in')]),
      p(classes: 'subtitle', [.text('Loading sign-in options…')]),
    ]);
  }
}

class _SignInMessage extends StatelessComponent {
  const _SignInMessage(this.message);

  final String message;

  @override
  Component build(BuildContext context) {
    return div(classes: 'card', [
      h1(classes: 'title', [.text('Sign in')]),
      p(classes: 'subtitle', [.text(message)]),
    ]);
  }
}
