import 'package:revali_router/revali_router.dart';
import 'package:zonai_web/auth/auth_routes.dart';
import 'package:zonai_web/server/render_web_app.dart';

/// Serves embedded Jaspr static assets and SSR HTML under [AuthRoutes.mountPath].
class JasprWeb implements LifecycleComponent {
  const JasprWeb();

  WrapperResult wrap(Context context, NextResponse next) async {
    if (context.request.method != 'GET' && context.request.method != 'HEAD') {
      return next();
    }

    final path = context.request.uri.path;
    if (!AuthRoutes.isMountedWebPath(path)) {
      return next();
    }

    if (isJasprStaticAssetPath(path)) {
      final asset = await tryServeJasprAsset(toShelfRequest(context));
      if (asset == null) {
        return next();
      }

      await applyShelfResponse(context, asset);
      return context.response;
    }

    final rendered = await renderWebApp(toShelfRequest(context));
    applyJasprResponse(context, rendered);
    return context.response;
  }
}
