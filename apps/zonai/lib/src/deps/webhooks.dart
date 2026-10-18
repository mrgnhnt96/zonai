import 'package:scoped_deps/scoped_deps.dart';
import '../domain/webhook/webhooks.dart';

WebhooksCompiler? _webhooks;

final webhooksProvider = create<WebhooksCompiler>(
  () => _webhooks ??= WebhooksCompiler(),
);

WebhooksCompiler get webhooksCompiler => read(webhooksProvider);
