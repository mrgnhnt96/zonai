import 'dart:async';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_route_provider.dart';
import '../auth/auth_routes.dart';
import '../auth/supported_auth_types_provider.dart';
import 'sign_in_screen.dart';

/// Chooses the sign-in screen from supported auth types and the current path.
class LoginFlow extends StatelessComponent {
  const LoginFlow({super.key});

  @override
  Component build(BuildContext context) {
    final authTypes = context.watch(supportedAuthTypesProvider);
    final path = context.watch(authRouteProvider);

    if (authTypes.isEmpty) {
      return const SignInScreen(child: _SignInMessage('No sign-in methods are configured.'));
    }

    if (authTypes.length == 1 && path == AuthRoutes.signIn) {
      if (!context.binding.isClient) {
        return switch (authTypes.single) {
          .password => const PasswordSignInScreen(),
        };
      }
      return _RedirectToAuthType(authType: authTypes.single);
    }

    final selected = AuthRoutes.typeFromPath(path);
    if (selected != null && authTypes.contains(selected)) {
      return switch (selected) {
        .password => const PasswordSignInScreen(),
      };
    }

    if (path != AuthRoutes.signIn) {
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
