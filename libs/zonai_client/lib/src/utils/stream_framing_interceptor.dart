import 'dart:async';
import 'dart:developer' as developer;

import 'package:revali_client/revali_client.dart';
import 'package:zonai_client/src/utils/json_value_framer.dart';

/// Called with each error on a live `/db/stream*` response: a message that
/// could not be framed, or the connection failing.
typedef StreamErrorReporter =
    void Function(Uri url, Object error, StackTrace? stackTrace);

/// Hands the generated `/db/stream*` readers one whole JSON message per chunk.
///
/// The generated `DbDataSource.streamOne` / `streamList` / `streamCount`
/// decode every chunk they receive as its own JSON message and drop the ones
/// that fail. The network does not keep message boundaries, so a message
/// bigger than one read never decoded and its listener never heard of it.
/// This re-chunks those responses with [JsonValueFramer] before they reach
/// that code.
///
/// The generated readers also swallow every stream error, so this reports
/// them to [onError] on their way past; the default logs them under the
/// `zonai_client` name. To report them somewhere else, build the client with
/// `ZonaiClient.server` from a `Server` that already carries one of these.
class StreamFramingInterceptor implements HttpInterceptor {
  const StreamFramingInterceptor({this.onError = _log});

  final StreamErrorReporter onError;

  static final _streamPath = RegExp(r'/db/stream(/list|/count)?/?$');

  @override
  FutureOr<HttpResponse?> onRequest(HttpRequest request) => null;

  @override
  FutureOr<HttpResponse?> onResponse(HttpResponse response) {
    final url = response.request.url;
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok || !_streamPath.hasMatch(url.path)) {
      return null;
    }

    return HttpResponse(
      request: response.request,
      statusCode: response.statusCode,
      headers: response.headers,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
      contentLength: response.contentLength,
      stream: response
          .transform(const JsonValueFramer())
          .transform(
            StreamTransformer.fromHandlers(
              handleError: (error, stackTrace, sink) {
                onError(url, error, stackTrace);
                sink.addError(error, stackTrace);
              },
            ),
          ),
    );
  }
}

void _log(Uri url, Object error, StackTrace? stackTrace) {
  developer.log(
    'Live stream ${url.path} failed',
    name: 'zonai_client',
    error: error,
    stackTrace: stackTrace,
  );
}
