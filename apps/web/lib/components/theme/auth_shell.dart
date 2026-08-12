import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';

import '../../auth/auth_route_provider.dart';
import '../../auth/auth_routes.dart';
import '../../auth/supported_auth_types_provider.dart';
import '../../providers/app_name_provider.dart';
import '../../providers/brand_logo_provider.dart';
import 'ui_styles.dart';
import 'zonai_button.dart';
import 'zonai_card.dart';
import 'zonai_typography.dart';

/// Brand block shown above auth cards (app name from SSR config).
class AuthBrand extends StatelessComponent {
  const AuthBrand({super.key, this.tagline = 'Sign in to your workspace'});

  final String tagline;

  @override
  Component build(BuildContext context) {
    final appName = context.watch(appNameProvider);
    final hasBrandLogo = context.watch(hasBrandLogoProvider);
    final initial = appName.isNotEmpty ? appName[0].toUpperCase() : 'Z';

    return div(classes: ZonaiClasses.authBrand, [
      if (hasBrandLogo)
        img(src: brandLogoUrl, alt: appName, classes: '${ZonaiClasses.authLogo} ${ZonaiClasses.authLogoImage}')
      else
        div(classes: ZonaiClasses.authLogo, [.text(initial)]),
      h2(classes: ZonaiClasses.authAppName, [.text(appName)]),
      p(classes: ZonaiClasses.authTagline, [.text(tagline)]),
    ]);
  }
}

/// Centered auth column: brand header + card content.
class AuthShell extends StatelessComponent {
  const AuthShell({super.key, required this.children, this.tagline = 'Sign in to your workspace'});

  final List<Component> children;
  final String tagline;

  @override
  Component build(BuildContext context) {
    return div(classes: ZonaiClasses.authLayout, [AuthBrand(tagline: tagline), ...children]);
  }
}

/// Navigates to a prior step in the sign-in flow (method picker, password form, etc.).
class AuthBackButton extends StatelessComponent {
  const AuthBackButton({super.key, required this.to});

  final String to;

  @override
  Component build(BuildContext context) {
    return ZonaiButton(variant: ZonaiButtonVariant.ghost, onClick: () => context.goApp(to), child: .text('← Back'));
  }
}

/// Back control when the current route has a meaningful parent in the auth flow.
class AuthBackIfNeeded extends StatelessComponent {
  const AuthBackIfNeeded({super.key});

  @override
  Component build(BuildContext context) {
    final path = context.watch(authRouteProvider);
    final authTypes = context.watch(supportedAuthTypesProvider);
    final back = AuthRoutes.backPath(path, authTypes);
    if (back == null) {
      return Component.empty();
    }
    return AuthBackButton(to: back);
  }
}

/// Standard auth card wrapping form content.
class AuthFormCard extends StatelessComponent {
  const AuthFormCard({super.key, required this.children});

  final List<Component> children;

  @override
  Component build(BuildContext context) {
    return ZonaiCard(children: children);
  }
}

/// Tappable row for choosing a sign-in method.
class AuthMethodTile extends StatelessComponent {
  const AuthMethodTile({super.key, required this.title, required this.description, required this.onSelect});

  final String title;
  final String description;
  final void Function() onSelect;

  @override
  Component build(BuildContext context) {
    return button(type: .button, classes: ZonaiClasses.authMethod, onClick: onSelect, [
      span(classes: ZonaiClasses.authMethodTitle, [.text(title)]),
      span(classes: ZonaiClasses.authMethodDesc, [.text(description)]),
    ]);
  }
}

/// Primary + secondary action stack inside a form.
class AuthActions extends StatelessComponent {
  const AuthActions({super.key, required this.children});

  final List<Component> children;

  @override
  Component build(BuildContext context) {
    return div(classes: ZonaiClasses.authActions, children);
  }
}

/// Centered text link for secondary navigation (e.g. forgot password).
class AuthTextLink extends StatelessComponent {
  const AuthTextLink({super.key, required this.label, required this.onClick});

  final String label;
  final void Function() onClick;

  @override
  Component build(BuildContext context) {
    return div(classes: ZonaiClasses.authFooter, [
      button(type: .button, classes: ZonaiClasses.authLink, onClick: onClick, [.text(label)]),
    ]);
  }
}

/// Icon + title block for post-submit “check your email” states.
class AuthSentHeader extends StatelessComponent {
  const AuthSentHeader({super.key, required this.title, required this.subtitle, this.icon = '✉'});

  final String title;
  final String subtitle;
  final String icon;

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      div(classes: ZonaiClasses.authSentIcon, [.text(icon)]),
      ZonaiPageTitle(title),
      ZonaiPageSubtitle(subtitle),
    ]);
  }
}

/// Convenience primary submit button for auth forms.
class AuthSubmitButton extends StatelessComponent {
  const AuthSubmitButton({
    super.key,
    required this.label,
    this.loadingLabel,
    this.loading = false,
    this.type = ButtonType.submit,
  });

  final String label;
  final String? loadingLabel;
  final bool loading;
  final ButtonType type;

  @override
  Component build(BuildContext context) {
    return ZonaiButton(
      type: type,
      fullWidth: true,
      disabled: loading,
      child: .text(loading && loadingLabel != null ? loadingLabel! : label),
    );
  }
}
