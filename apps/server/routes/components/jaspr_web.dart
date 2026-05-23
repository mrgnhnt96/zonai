import 'package:revali_router/revali_router.dart';
import 'package:zonai_web/server/render_web_app.dart';

/// Serves embedded Jaspr static assets and SSR HTML.
class JasprWeb implements LifecycleComponent {
  const JasprWeb();

  WrapperResult wrap(Context context, NextResponse next) async {
    if (context.request.method != 'GET' && context.request.method != 'HEAD') {
      return next();
    }

    final path = context.request.uri.path;
    if (isJasprStaticAssetPath(path)) {
      final asset = await tryServeJasprAsset(toShelfRequest(context));
      if (asset == null) {
        return next();
      }

      await applyShelfResponse(context, asset);
      return context.response;
    }

    if (_isApiPath(path)) {
      return next();
    }

    final rendered = await renderWebApp(toShelfRequest(context));
    applyJasprResponse(context, rendered);
    return context.response;
  }
}

bool _isApiPath(String path) {
  if (path == '/health') {
    return true;
  }

  const apiPrefixes = ['/auth', '/db', '/email'];
  for (final prefix in apiPrefixes) {
    if (path == prefix || path.startsWith('$prefix/')) {
      return true;
    }
  }

  return false;
}
