import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:zonai_schema/payloads.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_routes.dart';
import '../auth/supported_auth_types_provider.dart';
import '../components/magic_link_sign_in_screen.dart' deferred as magic_link_sign_in;
import '../components/magic_link_verify_screen.dart' deferred as magic_link_verify;
import '../components/otp_sign_in_screen.dart' deferred as otp_sign_in;
import '../components/reset_password_confirm_screen.dart' deferred as reset_password_confirm;
import '../components/reset_password_request_screen.dart' deferred as reset_password_request;
import '../components/sign_in_screen.dart';
import '../components/theme/theme_components.dart';
import '../components/verify_email_screen.dart' deferred as verify_email;
import 'route_path_sync.dart';
import 'router_error.dart';

/// Router for unauthenticated flows inside [AuthAppShell].
class AuthRouter extends StatelessComponent {
  const AuthRouter({required this.initialPath, super.key});

  /// Normalized app path from SSR (see [AuthAppShell.initialPath]).
  final String initialPath;

  @override
  Component build(BuildContext context) {
    return Router(
      errorBuilder: routerErrorBuilder(initialPath),
      redirect: _redirect,
      routes: [
        ShellRoute(
          builder: (_, _, child) => RoutePathSync(child: child),
          routes: authRoutes,
        ),
      ],
    );
  }

  static String? _redirect(BuildContext context, RouteState state) {
    if (AuthRoutes.routerRedirectToMountedLocation(state.location) case final mountedRedirect?) {
      return mountedRedirect;
    }

    final path = AuthRoutes.normalizePath(state.location);
    if (path == AuthRoutes.home) {
      if (_isSignedIn(context)) {
        return null;
      }
      return AuthRoutes.toUrlPath(AuthRoutes.signIn);
    }

    final singleAuth = _redirectSingleAuthType(context, path);
    if (singleAuth != null) {
      return singleAuth;
    }

    if (!AuthRoutes.isPublicAuthPath(path) && authTypesOrEmpty(context).isNotEmpty) {
      return AuthRoutes.toUrlPath(AuthRoutes.forType(authTypesOrEmpty(context).first));
    }

    return null;
  }

  static String? _redirectSingleAuthType(BuildContext context, String path) {
    if (!context.binding.isClient || !AuthRoutes.isSignInRoot(path)) {
      return null;
    }

    final authTypes = authTypesOrEmpty(context);
    if (authTypes.length != 1) {
      return null;
    }

    final selected = AuthRoutes.typeFromPath(path);
    if (selected == authTypes.single) {
      return null;
    }

    return AuthRoutes.toUrlPath(AuthRoutes.forType(authTypes.single));
  }
}

List<AuthType> authTypesOrEmpty(BuildContext context) {
  return ProviderScope.containerOf(context).read(supportedAuthTypesProvider);
}

bool _isSignedIn(BuildContext context) {
  if (!context.binding.isClient) {
    return false;
  }
  return ProviderScope.containerOf(context).read(authProvider);
}

final List<RouteBase> authRoutes = [
  Route.lazy(
    path: '${AuthRoutes.mountPath}${AuthRoutes.verifyEmailCallback}',
    name: 'verify-email',
    builder: (_, _) => verify_email.VerifyEmailScreen(),
    load: verify_email.loadLibrary,
  ),
  Route.lazy(
    path: '${AuthRoutes.mountPath}${AuthRoutes.magicLinkCallback}',
    name: 'magic-link-callback',
    builder: (_, _) => magic_link_verify.MagicLinkVerifyScreen(),
    load: magic_link_verify.loadLibrary,
  ),
  Route.lazy(
    path: '${AuthRoutes.mountPath}${AuthRoutes.resetPasswordCallback}',
    name: 'reset-password-callback',
    builder: (_, _) => reset_password_confirm.ResetPasswordConfirmScreen(),
    load: reset_password_confirm.loadLibrary,
  ),
  Route.lazy(
    path: '${AuthRoutes.mountPath}${AuthRoutes.resetPasswordRequest}',
    name: 'reset-password-request',
    builder: (_, _) => reset_password_request.ResetPasswordRequestScreen(),
    load: reset_password_request.loadLibrary,
  ),
  Route(
    path: '${AuthRoutes.mountPath}${AuthRoutes.signIn}',
    name: 'sign-in',
    redirect: (context, state) => AuthRouter._redirectSingleAuthType(context, AuthRoutes.normalizePath(state.location)),
    builder: (context, state) => _SignInRootScreen(path: AuthRoutes.normalizePath(state.location)),
    routes: [
      Route(path: 'password', name: 'sign-in-password', builder: (_, _) => const PasswordSignInScreen()),
      Route.lazy(
        path: 'otp',
        name: 'sign-in-otp',
        builder: (_, _) => otp_sign_in.OtpSignInScreen(),
        load: otp_sign_in.loadLibrary,
      ),
      Route.lazy(
        path: 'magicLink',
        name: 'sign-in-magic-link',
        builder: (_, _) => magic_link_sign_in.MagicLinkSignInScreen(),
        load: magic_link_sign_in.loadLibrary,
      ),
    ],
  ),
];

class _SignInRootScreen extends StatelessComponent {
  const _SignInRootScreen({required this.path});

  final String path;

  @override
  Component build(BuildContext context) {
    final authTypes = context.watch(supportedAuthTypesProvider);

    if (authTypes.isEmpty) {
      return const SignInScreen(child: _SignInMessage('No sign-in methods are configured.'));
    }

    if (authTypes.length == 1 && AuthRoutes.isSignInRoot(path)) {
      if (!context.binding.isClient) {
        return switch (authTypes.single) {
          AuthType.password => const PasswordSignInScreen(),
          AuthType.otp => otp_sign_in.OtpSignInScreen(),
          AuthType.magicLink => magic_link_sign_in.MagicLinkSignInScreen(),
        };
      }
      return const _SignInLoading();
    }

    return const AuthTypePickerScreen();
  }
}

class _SignInLoading extends StatelessComponent {
  const _SignInLoading();

  @override
  Component build(BuildContext context) {
    return const SignInScreen(
      child: AuthFormCard(children: [ZonaiPageTitle('Sign in'), ZonaiPageSubtitle('Loading sign-in options…')]),
    );
  }
}

class _SignInMessage extends StatelessComponent {
  const _SignInMessage(this.message);

  final String message;

  @override
  Component build(BuildContext context) {
    return SignInScreen(child: AuthFormCard(children: [const ZonaiPageTitle('Sign in'), ZonaiPageSubtitle(message)]));
  }
}
