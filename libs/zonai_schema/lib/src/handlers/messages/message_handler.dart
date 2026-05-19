// dart format width=100
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:zonai_schema/src/handlers/messages/stdin.dart';
import 'package:zonai_schema/src/handlers/messages/stdout.dart';
import 'package:zonai_schema/src/types/built_in_emails.dart';
import 'package:zonai_schema/zonai_schema.dart';

part 'deps/__get.dart';
part 'deps/__log.dart';
part 'deps/__mutate.dart';
part 'deps/__email.dart';
part 'request.dart';
part 'response.dart';

class MessageHandler {
  MessageHandler({required this.onMessage, Stdin? stdin, Stdout? stdout})
    : stdin = Stdin(),
      stdout = Stdout();

  final Future<Response?> Function(UnknownRequest) onMessage;
  final Stdin stdin;
  final Stdout stdout;

  final Map<String, Completer<Response>> _pendingHostReplies = {};

  bool _listening = false;
  Future<void> listen() async {
    Future<void> _listen() async {
      if (_listening) return;
      _listening = true;

      final stream = stdin.stream.transform(utf8.decoder).transform(const LineSplitter());

      queue:
      await for (final line in stream) {
        final message = line.trim();
        if (message.isEmpty) continue;
        if (message case 'kill' || 'quit' || 'exit' || 'q') {
          break;
        }

        final map = _tryJsonObject(message);
        if (map == null) continue;

        final pathRaw = map['path'];

        if (pathRaw is String && pathRaw.startsWith(Response.prefix)) {
          Response? response;
          try {
            response = Response.fromJson(map);
          } catch (e, stack) {
            logger.error('Invalid response JSON', error: '$e', stackTrace: '$stack');
            continue;
          }
          if (_pendingHostReplies.containsKey(response.id)) {
            _deliverHostReply(response);
            continue;
          }
          logger.warn(
            'Ignoring response JSON with no pending id',
            properties: switch (response) {
              MessageErrorResponse(:final message, :final error) => {
                'path': pathRaw,
                'id': response.id,
                'error_message': message,
                'cause': error ?? '(null)',
              },
              _ => {'path': pathRaw, 'id': response.id},
            },
          );
          continue;
        }

        if (pathRaw is! String || !pathRaw.startsWith(Request.prefix)) {
          logger.error(
            'Invalid stdin message path (expected ${Request.prefix})',
            properties: {'path': pathRaw},
          );
          continue;
        }

        Request request;
        try {
          request = Request.fromJson(map);
        } catch (e, stack) {
          logger.error(
            'Invalid request JSON for path "$pathRaw"',
            error: '$e',
            stackTrace: '$stack',
          );
          continue;
        }

        switch (request) {
          case RequestPing():
            reply(PongResponse(id: request.id));
            continue;
          case RequestKill():
            break queue;
          case final UnknownRequest request:
            runMergedScoped(
              () async {
                onMessage(request).then(
                  reply,
                  onError: (Object error, StackTrace stackTrace) {
                    logger.debug(
                      'Error handling request',
                      properties: {'request': request.toJson(), 'error': e.toString()},
                    );
                    reply(
                      MessageErrorResponse(
                        id: request.id,
                        message: 'Error handling request',
                        error: error.toString(),
                        stackTrace: stackTrace.toString(),
                      ),
                    );
                  },
                );
              },
              includeIfAbsent: {
                _emailProvider.overrideWith(
                  () => _Email(
                    (email) {
                      sendRequest(SendEmailRequest(email));
                    },
                    (builtIn, to, variables) {
                      sendRequest(SendBuiltInEmailRequest(builtIn, to: to, variables: variables));
                    },
                  ),
                ),
                _mutateProvider.overrideWith(
                  () => _Mutate(
                    update: ({required collection, required updates, required where, limit}) async {
                      await sendRequest(
                        UpdateRecordRequest(
                          collection: collection,
                          updates: updates,
                          where: where,
                          jwt: request.jwt,
                          parent: request,
                        ),
                        expectResponse: false,
                      );
                    },
                    delete: ({required collection, required updates, required where, limit}) async {
                      await sendRequest(
                        DeleteRecordRequest(
                          collection: collection,
                          where: where,
                          parent: request,
                          jwt: request.jwt,
                        ),
                        expectResponse: false,
                      );
                    },
                    create: ({required collection, required objects}) async {
                      await sendRequest(
                        CreateRecordRequest(
                          collection: collection,
                          objects: objects,
                          parent: request,
                          jwt: request.jwt,
                        ),
                        expectResponse: false,
                      );
                    },
                  ),
                ),
              },
            );
          case _:
            reply(
              MessageErrorResponse(
                id: request.id,
                message: 'Unhandled request',
                error: 'Unhandled request ${request.runtimeType}(${request.path})',
              ),
            );
        }
      }

      for (final completer in _pendingHostReplies.values) {
        completer.completeError(StateError('MessageHandler stopped before the host replied'));
      }
      _pendingHostReplies.clear();
      _listening = false;
    }

    await runZoned(
      () async {
        await runScoped(
          _listen,
          values: {
            _getRecordRequestProvider.overrideWith(
              () => _Get(({required collection, required where, limit, offset, jwt}) async {
                final result = await sendRequest(
                  GetRecordRequest(
                    collection: collection,
                    where: where,
                    limit: limit,
                    offset: offset,
                    jwt: jwt,
                  ),
                );

                if (result case GetRecordResponse(:final records)) {
                  return records;
                } else {
                  logger.error(
                    'Received unexpected response for get record request ${result?.path}',
                  );
                  logger.debug('Unexpected Response: ${result?.toJson()}');
                }

                return null;
              }),
            ),
            _loggerProvider.overrideWith(
              () => _Logger((message, {required level, properties, stackTrace, error}) {
                reply(
                  DebugResponse(
                    message: message,
                    level: level,
                    properties: properties,
                    stackTrace: stackTrace,
                    error: error,
                  ),
                );
              }),
            ),
          },
        );
      },
      zoneSpecification: .new(
        print: (_, _, _, message) {
          reply(DebugResponse(message: message, level: .info));
        },
      ),
    );
  }

  /// Asks the host process (main thread) for data by writing [request] as JSON
  /// to stdout and waiting for a matching [Response] on stdin (same [id]).
  ///
  /// A host [MessageErrorResponse] is turned into [MessageHandlerFailedException].
  Future<Response?> sendRequest(Request request, {bool expectResponse = true}) async {
    if (!_listening) {
      assert(false, 'Cannot send a request while not listening');
      return null;
    }
    Completer<Response>? completer;
    if (expectResponse) {
      completer = Completer<Response>();
      _pendingHostReplies[request.id] = completer;
    }

    final String json;
    try {
      json = jsonEncode(request.toJson());
    } catch (e) {
      _pendingHostReplies.remove(request.id);
      assert(false, 'Failed to encode request: $e');
      return null;
    }

    stdout.writeln(json);

    return await completer?.future;
  }

  void reply(Response? message) {
    if (message == null) return;
    assert(_listening, 'Cannot send a message while not listening');

    String json;
    try {
      json = jsonEncode(message);
    } catch (e) {
      assert(false, 'Failed to encode message: $e');
      print('Failed to encode message: $e');
      return;
    }

    stdout.writeln(json);
  }

  void _deliverHostReply(Response response) {
    final completer = _pendingHostReplies.remove(response.id);
    if (completer == null) {
      logger.error('Received response for unknown request: ${response.id}');
      return;
    }
    try {
      if (response is MessageErrorResponse) {
        completer.completeError(
          MessageHandlerFailedException(
            response.message,
            cause: response.error,
            causeStackTrace: response.stackTrace,
          ),
        );
      } else {
        completer.complete(response);
      }
    } on Object catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }

  Map<String, dynamic>? _tryJsonObject(String message) {
    try {
      return switch (jsonDecode(message)) {
        final Map<String, dynamic> json => json,
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    stdin.dispose();
    stdout.dispose();
  }
}
